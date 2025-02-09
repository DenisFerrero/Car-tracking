export default defineNuxtConfig({
  compatibilityDate: '2024-11-01',
  devtools: { enabled: true },

  css: ['~/assets/css/main.scss'],

  plugins: [{ src: '~/plugins/socket.client.js', ssr: false }],

  runtimeConfig: {
    public: {
      server: process.env.SERVER || 'http://localhost:4000'
    }
  },

  app: {
    head: {
      link: [
        { rel: 'icon', type: 'image/x-icon', href: '/favicon.ico'  }
      ]
    }
  },

  modules: ['@nuxt/eslint', '@nuxtjs/leaflet']
})