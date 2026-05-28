import { defineEventHandler, getRequestHeaders } from 'h3'

export default defineEventHandler((event) => {
  const headers = getRequestHeaders(event)
  
  // Nginx proxies these headers from Authelia to the Nuxt server
  const username = headers['remote-user'] || ''
  const name = headers['remote-name'] || ''
  const email = headers['remote-email'] || ''
  const groups = headers['remote-groups'] || ''

  return {
    authenticated: !!username,
    username,
    name,
    email,
    groups: groups ? groups.split(',') : []
  }
})
