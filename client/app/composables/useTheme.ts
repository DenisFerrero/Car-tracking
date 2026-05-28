import { ref } from 'vue'

const currentTheme = ref<'dark' | 'light'>('dark')

export function useTheme() {
  const applyTheme = (theme: 'dark' | 'light') => {
    currentTheme.value = theme
    if (import.meta.client) {
      document.documentElement.setAttribute('data-theme', theme)
      localStorage.setItem('user-theme', theme)
    }
  }

  const initTheme = () => {
    if (import.meta.client) {
      const saved = localStorage.getItem('user-theme')
      if (saved === 'dark' || saved === 'light') {
        applyTheme(saved)
      } else {
        applyTheme('dark')
      }
    }
  }

  const toggleTheme = () => {
    const nextTheme = currentTheme.value === 'dark' ? 'light' : 'dark'
    applyTheme(nextTheme)
  }

  return {
    theme: currentTheme,
    initTheme,
    toggleTheme,
    setTheme: applyTheme
  }
}
