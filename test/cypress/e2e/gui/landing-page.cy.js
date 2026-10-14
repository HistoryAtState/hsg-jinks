// StandardJS, should-style assertions
// GUI tests for the HSG landing page (app-owned — skip-listed in config.json,
// replaces the generated demo-landing spec)

describe('HSG Landing Page', () => {
  beforeEach(() => {
    cy.visit('/index.html')
    cy.get('body').should('be.visible')
  })

  describe('Structure', () => {
    it('loads without the error template', () => {
      cy.title().should('not.be.empty').and('not.contain', 'Ooops')
    })

    it('has the landing page layout class', () => {
      cy.get('pb-page').should('have.class', 'landing-layout')
    })

    it('shows no demo sections', () => {
      cy.get('[class*="highlight-card"]').should('not.exist')
      cy.get('.team-members').should('not.exist')
    })
  })

  describe('Banner', () => {
    it('shows no flag, the office logo carries it', () => {
      cy.get('.usa-banner__header-flag').should('not.be.visible')
    })
  })

  describe('Hero', () => {
    it('renders the title, mission statement and action link above the media band', () => {
      cy.get('section.hero-title h1').should('contain', 'The Office of the Historian')
      cy.get('section.hero-title .hero-title__text p').invoke('text').should('have.length.greaterThan', 50)
      cy.get('section.hero-title .hero-title__text ul.buttons a').should('contain', 'Read More About Us')
      cy.get('section.hero-title + div.hero-media[role="img"]').should('exist')
    })

    it('has no separate intro band', () => {
      cy.get('.section-intro').should('not.exist')
    })
  })

  describe('Latest Publications', () => {
    it('is not shown', () => {
      cy.get('.section-publications').should('not.exist')
    })
  })

  describe('Latest News', () => {
    // Requires the carousel data package (/db/apps/carousel) in the test
    // instance; the section is hidden gracefully when it is missing. Slides
    // follow its display-order.xml, so counts are relative, not fixed.
    const withNews = (fn) => {
      cy.get('body').then(($body) => {
        if ($body.find('.section-news').length === 0) {
          cy.log('carousel package not installed — section hidden')
          return
        }
        fn()
      })
    }

    it('renders one card with a date and a dot per slide', () => {
      withNews(() => {
        cy.get('.section-news .hsg-carousel__slide').should('have.length.at.least', 1).then(($slides) => {
          cy.get('.section-news .usa-card .card-date').should('have.length', $slides.length)
          cy.get('.section-news .hsg-carousel__dot').should('have.length', $slides.length)
        })
        cy.get('.section-news .usa-card h3.usa-card__heading a').first()
          .should('have.attr', 'href')
      })
    })

    it('is a white band', () => {
      withNews(() => {
        cy.get('.section-news').should('have.css', 'background-color', 'rgb(255, 255, 255)')
      })
    })

    it('hides arrows and dots while every slide fits', () => {
      cy.viewport(1280, 900)
      withNews(() => {
        cy.get('.hsg-carousel__slide').then(($slides) => {
          if ($slides.length > 3) return
          cy.get('.hsg-carousel').should('have.class', 'hsg-carousel--static')
          cy.get('.hsg-carousel__arrows').should('not.be.visible')
          cy.get('.hsg-carousel__dots').should('not.be.visible')
        })
      })
    })

    it('scrolls one slide per arrow click on a phone', () => {
      cy.viewport(390, 844)
      withNews(() => {
        cy.get('.hsg-carousel__slide').then(($slides) => {
          if ($slides.length < 2) return
          cy.get('.hsg-carousel').should('not.have.class', 'hsg-carousel--static')
          cy.get('.hsg-carousel__prev').should('be.disabled')
          cy.get('.hsg-carousel__dot').first().should('have.attr', 'aria-current', 'true')
          cy.get('.hsg-carousel__next').click()
          cy.get('.hsg-carousel__dot').eq(1).should('have.attr', 'aria-current', 'true')
          cy.get('.hsg-carousel__prev').should('not.be.disabled')
        })
      })
    })
  })
})
