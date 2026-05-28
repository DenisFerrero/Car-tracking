<template>
  <div class="glass-panel p-5 flex flex-col transition-all duration-300">
    <div class="flex justify-between items-center mb-4">
      <h4 class="text-base font-bold text-title flex items-center m-0">
        <span class="mr-2">🎛️</span> {{ t('deviceCardTitle') }}
      </h4>
      <nuxt-link to="/" class="px-3.5 py-1.5 rounded-lg text-xs font-semibold bg-gradient-to-br from-indigo-500 to-indigo-600 hover:from-indigo-600 hover:to-indigo-700 text-white shadow-md hover:shadow-lg transition duration-200 cursor-pointer">
        {{ t('allDevices') }}
      </nuxt-link>
    </div>
    
    <div class="flex flex-col gap-2 rounded-xl">
      <!-- Device ID -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('devId') }}</span>
        <span class="font-mono text-xs break-all text-right max-w-[60%] text-title">{{ props.device.id }}</span>
      </div>

      <!-- Device Name -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('devName') }}</span>
        <span class="font-bold text-sm text-title">{{ props.device.name }}</span>
      </div>

      <!-- IMEI -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('devImei') }}</span>
        <span class="font-mono text-sm text-title">{{ props.device.imei }}</span>
      </div>

      <!-- Manufacturer -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('devManufacturer') }}</span>
        <span v-if="typeof props.device.manufacturer === 'string'" class="font-bold text-sm text-title">{{ props.device.manufacturer }}</span>
        <span v-else class="italic text-xs text-text-muted">{{ t('notDefined') }}</span>
      </div>

      <!-- Model -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('devModel') }}</span>
        <span v-if="typeof props.device.model === 'string'" class="font-bold text-sm text-title">{{ props.device.model }}</span>
        <span v-else class="italic text-xs text-text-muted">{{ t('notDefined') }}</span>
      </div>

      <!-- Revision -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('devRevision') }}</span>
        <span v-if="typeof props.device.revision === 'string'" class="px-2.5 py-1 rounded-full text-xs font-semibold bg-badge-bg text-badge-text border border-card-border/50">{{ props.device.revision }}</span>
        <span v-else class="italic text-xs text-text-muted">{{ t('notDefined') }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { useI18n } from '~/composables/useI18n'
const { t } = useI18n()

const props = defineProps({
  device: {
    type: Object,
    default: () => {}
  }
})
</script>