// API tests for the OPDS catalog (OP#1105 / #1206 / #1207) -- a pure
// machine API, no HTML anywhere, so these assert directly against the
// Atom/JSON response bodies rather than the DOM. Unauthenticated by design
// (no cy.login()): real OPDS e-reader clients can't do this app's
// cookie/basic-auth handshake.

const parseAtom = (body) => Cypress.$.parseXML(body)

describe('OPDS Catalog API', () => {
  describe('GET /api/v1/catalog', () => {
    it('returns a navigation feed linking to All, Recent and Browse', () => {
      cy.request('/api/v1/catalog').then((response) => {
        expect(response.status).to.eq(200)
        expect(response.headers['content-type']).to.contain('application/atom+xml;profile=opds-catalog;kind=navigation')
        const $feed = Cypress.$(parseAtom(response.body))
        const titles = $feed.find('entry > title').map((_, el) => el.textContent).get()
        expect(titles).to.include.members(['All', 'Recent', 'Browse'])
      })
    })
  })

  describe('GET /api/v1/catalog/all', () => {
    it('returns an acquisition feed with at least one ebook volume', () => {
      cy.request('/api/v1/catalog/all').then((response) => {
        expect(response.status).to.eq(200)
        expect(response.headers['content-type']).to.contain('application/atom+xml;profile=opds-catalog;kind=acquisition')
        const $feed = Cypress.$(parseAtom(response.body))
        expect($feed.find('entry').length).to.be.at.least(1)
        // every acquisition link's href must match its own declared type
        // (the #1203 rework item: hsg-shell had a live report of a PDF link
        // pointing at an .epub href)
        $feed.find('entry > link[type="application/epub+zip"]').each((_, link) => {
          expect(link.getAttribute('href')).to.match(/\.epub$/)
        })
        $feed.find('entry > link[type="application/pdf"]').each((_, link) => {
          expect(link.getAttribute('href')).to.match(/\.pdf$/)
        })
      })
    })
  })

  describe('GET /api/v1/catalog/recent', () => {
    // Regression guard: the sort casts tei:change/@when to xs:date, and the
    // corpus does not guarantee a full YYYY-MM-DD -- frus1861 carries
    // when="1861" and frus1958-60v05mSupp has no matching tei:change at all.
    // An unguarded cast took the whole feed down with a 500, so assert the
    // undated volumes are carried rather than fatal.
    it('serves every ebook volume, including ones with an imprecise or missing date', () => {
      cy.request('/api/v1/catalog/recent').then((response) => {
        expect(response.status).to.eq(200)
        expect(response.headers['content-type']).to.contain('application/atom+xml;profile=opds-catalog;kind=acquisition')
        const $recent = Cypress.$(parseAtom(response.body))
        cy.request('/api/v1/catalog/all').then((all) => {
          const $all = Cypress.$(parseAtom(all.body))
          expect($recent.find('entry').length).to.eq($all.find('entry').length)
        })
      })
    })

    it('truncates to n entries', () => {
      cy.request('/api/v1/catalog/recent?n=1').then((response) => {
        expect(response.status).to.eq(200)
        const $feed = Cypress.$(parseAtom(response.body))
        expect($feed.find('entry').length).to.be.at.most(1)
      })
    })

    it('returns 400 JSON for a non-numeric n', () => {
      cy.request({ url: '/api/v1/catalog/recent?n=abc', failOnStatusCode: false }).then((response) => {
        expect(response.status).to.eq(400)
        expect(response.body).to.have.property('code')
        expect(response.body).to.have.property('description')
      })
    })

    it('returns 400 JSON for a non-positive n', () => {
      cy.request({ url: '/api/v1/catalog/recent?n=0', failOnStatusCode: false }).then((response) => {
        expect(response.status).to.eq(400)
        expect(response.body).to.have.property('code')
      })
    })
  })

  describe('GET /api/v1/catalog/browse', () => {
    it('returns the 3 top-level taxonomy categories with no tag', () => {
      cy.request('/api/v1/catalog/browse').then((response) => {
        expect(response.status).to.eq(200)
        expect(response.headers['content-type']).to.eq('application/atom+xml;profile=opds-catalog')
        const $feed = Cypress.$(parseAtom(response.body))
        const ids = $feed.find('entry > id').map((_, el) => el.textContent).get()
        expect(ids).to.include.members(['people', 'places', 'topics'])
      })
    })

    it('returns 404 JSON for an unknown tag', () => {
      cy.request({ url: '/api/v1/catalog/browse?tag=not-a-real-tag', failOnStatusCode: false }).then((response) => {
        expect(response.status).to.eq(404)
        expect(response.body).to.have.property('code', 'NOT_FOUND_404')
        expect(response.body).to.have.property('description')
      })
    })
  })

  describe('GET /api/v1/catalog/search', () => {
    it('returns an empty navigation feed when q is omitted', () => {
      cy.request('/api/v1/catalog/search').then((response) => {
        expect(response.status).to.eq(200)
        expect(response.headers['content-type']).to.contain('kind=navigation')
        const $feed = Cypress.$(parseAtom(response.body))
        expect($feed.find('entry').length).to.eq(0)
      })
    })

    it('returns 400 JSON for malformed Lucene syntax', () => {
      cy.request({ url: '/api/v1/catalog/search?q=' + encodeURIComponent('AND('), failOnStatusCode: false }).then((response) => {
        expect(response.status).to.eq(400)
        expect(response.body).to.have.property('code', 'BAD_REQUEST_400')
      })
    })
  })
})
