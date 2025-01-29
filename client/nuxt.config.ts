export default defineNuxtConfig({
  compatibilityDate: '2024-11-01',
  devtools: { enabled: true },

  css: ['~/assets/css/main.scss'],

  plugins: [{ src: '~/plugins/socket.client.js', ssr: false }],

  runtimeConfig: {
    public: {
      server: 'http://localhost:4000'
    }
  },

  modules: ['@nuxt/eslint', '@nuxtjs/leaflet']
})