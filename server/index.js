const http = require('http')
const fs = require('fs')

function notFound (req, res) {
  res.end('not found\n')
}

function root (req, res) {
  res.end('hello\n')
}

function urandom(req, res) {
  const r = fs.createReadStream('/dev/urandom')
  r.pipe(res)
  setTimeout(() => {
    r.unpipe()
  }, 1000)
  res.once('unpipe', () => {
    res.end()
  })
}

const routes = {
  '/': root,
  '/urandom': urandom
}

http.createServer((req, res) => {
  const route = routes[req.url] || notFound
  route(req, res)
}).listen(8000)
