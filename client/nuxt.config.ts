import tailwindcss from '@tailwindcss/vite';

export default defineNuxtConfig({
  compatibilityDate: '2024-11-01',
  future: {
    compatibilityVersion: 4
  },
  devtools: { enabled: true },
  ssr: false,

  vite: {
    plugins: [
      tailwindcss()
    ],
    server: {
      allowedHosts: ['car-tracking.local']
    }
  },

  css: [
    'leaflet/dist/leaflet.css',
    '~/assets/css/main.css'
  ],

  app: {
    head: {
      link: [
        { rel: 'icon', type: 'image/x-icon', href: '/favicon.ico'  }
      ]
    }
  },


  runtimeConfig: {
    public: {
      server: process.env.NUXT_PUBLIC_SERVER || 'https://car-tracking.local'
    }
  },

  modules: ['@nuxt/eslint', '@nuxtjs/leaflet']
})

