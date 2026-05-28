<template>
  <nav class="flex items-center justify-between px-4 sm:px-6 py-3 bg-navbar-bg border-b border-navbar-border backdrop-blur-md sticky top-0 z-50 text-navbar-text transition-colors duration-300">
    <div class="container mx-auto flex justify-between items-center w-full">
      <!-- Left side: Brand / App Name -->
      <nuxt-link to="/" class="flex items-center gap-2 text-xl font-bold tracking-tight text-title hover:opacity-90 transition duration-200">
        <span class="text-2xl">🏎️</span>
        <span class="hidden sm:inline">{{ t('brand') }}</span>
      </nuxt-link>

      <!-- Right side: Actions & User Info -->
      <div class="flex items-center gap-2 sm:gap-3">
        <!-- Locale Switcher Icon Button -->
        <button class="w-10 h-10 flex items-center justify-center rounded-full border border-btn-sec-border bg-btn-sec-bg hover:bg-btn-sec-hover text-body-text transition hover:scale-105 cursor-pointer font-bold text-xs" :title="t('language')" @click="toggleLocale" aria-label="Change Language">
          {{ locale.toUpperCase() }}
        </button>

        <!-- Theme Switcher Icon Button -->
        <button class="w-10 h-10 flex items-center justify-center rounded-full border border-btn-sec-border bg-btn-sec-bg hover:bg-btn-sec-hover text-body-text transition hover:scale-105 cursor-pointer text-base" :title="t('theme')" @click="toggleTheme" aria-label="Toggle Theme">
          {{ theme === 'dark' ? '☀️' : '🌙' }}
        </button>

        <!-- User Profile & Logout -->
        <div v-if="user?.authenticated" class="flex items-center border-l border-card-border/30 pl-2 sm:pl-4 gap-2 sm:gap-3">
          <!-- User Avatar Badge -->
          <div class="w-9 h-9 rounded-full bg-indigo-500 text-white flex items-center justify-center font-bold text-sm shadow-md shadow-indigo-500/30">
            {{ user.name ? user.name[0].toUpperCase() : user.username[0].toUpperCase() }}
          </div>
          <!-- User Info text -->
          <div class="hidden md:flex flex-col text-left leading-tight mr-1">
            <span class="font-semibold text-sm text-title">
              {{ user.name || user.username }}
            </span>
            <span v-if="user.groups?.includes('admins')" class="self-start text-[9px] px-1.5 py-0.5 rounded bg-indigo-500/20 text-indigo-400 font-semibold border border-indigo-500/30 mt-1">
              {{ t('admin') }}
            </span>
          </div>
          
          <!-- Logout Button -->
          <button class="px-3.5 py-1.5 rounded-lg text-sm font-medium bg-btn-sec-bg border border-btn-sec-border hover:bg-btn-sec-hover text-btn-sec-text transition cursor-pointer hover:border-indigo-500/30" @click="logout">
            {{ t('logout') }}
          </button>
        </div>
      </div>
    </div>
  </nav>
</template>

<script setup>
import { useI18n } from '~/composables/useI18n'
import { useTheme } from '~/composables/useTheme'
import { onMounted } from 'vue'

const { locale, setLocale, t } = useI18n()
const { theme, toggleTheme, initTheme } = useTheme()

// Initialize theme on mount
onMounted(() => {
  initTheme()
})

const user = useState('user-profile')

if (!user.value) {
  const { data } = await useFetch('/auth-user')
  user.value = data.value
}

function toggleLocale() {
  setLocale(locale.value === 'en' ? 'it' : 'en')
}

function logout() {
  const domain = window.location.host;
  const protocol = window.location.protocol;
  window.location.href = `${protocol}//auth.${domain}/logout?rd=${protocol}//${domain}/`;
}
</script>
