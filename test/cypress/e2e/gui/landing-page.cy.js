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

  describe('Hero', () => {
    it('renders the split hero with the Office title', () => {
      cy.get('section.hero-title h1').should('contain', 'The Office of the Historian')
      cy.get('div.hero-media[role="img"]').should('exist')
    })
  })

  describe('Intro', () => {
    it('renders the mission statement with an action link', () => {
      cy.get('.section-intro p').invoke('text').should('have.length.greaterThan', 50)
      cy.get('.section-intro ul.buttons a').should('contain', 'Read More About Us')
    })
  })

  describe('Latest Publications', () => {
    it('is not shown', () => {
      cy.get('.section-publications').should('not.exist')
    })
  })

  describe('Latest News', () => {
    // Requires the carousel data package (/db/apps/carousel) in the test
    // instance; the section is hidden gracefully when it is missing.
    it('renders three news cards with dates', () => {
      cy.get('body').then(($body) => {
        if ($body.find('.section-news').length === 0) {
          cy.log('carousel package not installed — section hidden')
          return
        }
        cy.get('.section-news .usa-card').should('have.length', 3)
        cy.get('.section-news .usa-card .card-date').should('have.length', 3)
        cy.get('.section-news .usa-card h3.usa-card__heading a').first()
          .should('have.attr', 'href')
      })
    })
  })
})
