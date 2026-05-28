<template>
  <div class="glass-panel p-5 flex flex-col transition-all duration-300">
    <div class="flex justify-between items-center mb-4">
      <h4 class="text-base font-bold text-title flex items-center m-0">
        <span class="mr-2">📍</span> {{ t('positionCardTitle') }}
      </h4>
      <a :href="'https://www.google.com/maps/place/' + props.coordinate.x + ',' + props.coordinate.y" class="px-3.5 py-1.5 rounded-lg text-xs font-semibold bg-gradient-to-br from-indigo-500 to-indigo-600 hover:from-indigo-600 hover:to-indigo-700 text-white shadow-md hover:shadow-lg transition duration-200 cursor-pointer flex items-center gap-1" target="_blank">
        <span class="mr-1">🗺️</span> {{ t('posGoogle') }}
      </a>
    </div>

    <div class="flex flex-col gap-2 rounded-xl">
      <!-- Latitude -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('posLat') }}</span>
        <span class="font-mono font-bold text-sm text-title">{{ props.coordinate.x?.toFixed(6) }}</span>
      </div>

      <!-- Longitude -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('posLng') }}</span>
        <span class="font-mono font-bold text-sm text-title">{{ props.coordinate.y?.toFixed(6) }}</span>
      </div>

      <!-- Altitude -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('posAltitude') }}</span>
        <span v-if="typeof props.coordinate.altitude === 'number'" class="font-semibold text-sm text-title">
          {{ props.coordinate.altitude?.toFixed(2) }} m
        </span>
        <span v-else class="italic text-xs text-text-muted">{{ t('notDefined') }}</span>
      </div>

      <!-- Pressure -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('posPressure') }}</span>
        <span v-if="typeof props.coordinate.pressure === 'number'" class="font-semibold text-sm text-title">
          {{ props.coordinate.pressure?.toFixed(2) }} atm
        </span>
        <span v-else class="italic text-xs text-text-muted">{{ t('notDefined') }}</span>
      </div>

      <!-- Temperature -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('posTemperature') }}</span>
        <span v-if="typeof props.coordinate.temperature === 'number'" class="font-bold text-sm text-cyan-400">
          {{ props.coordinate.temperature?.toFixed(1) }} °C
        </span>
        <span v-else class="italic text-xs text-text-muted">{{ t('notDefined') }}</span>
      </div>

      <!-- Last update -->
      <div class="flex justify-between items-center bg-list-item-bg hover:bg-list-item-hover border border-card-border/30 rounded-xl px-4 py-3 text-body-text transition duration-200">
        <span class="font-semibold text-xs text-text-muted tracking-wide uppercase">{{ t('posLastUpdate') }}</span>
        <span class="text-xs font-semibold text-title">{{ formatDate(props.coordinate.timestamp) }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { useI18n } from '~/composables/useI18n'
const { t } = useI18n()

const props = defineProps({
  coordinate: {
    type: Object,
    default: () => {}
  }
})

function formatDate (_date) {
  if (!_date) return '';
  const date = new Date(_date);

  return ("00" + date.getDate()).slice(-2)
    + "/" + ("00" + (date.getMonth() + 1)).slice(-2) 
    + "/" + date.getFullYear() + " " 
    + ("00" + date.getHours()).slice(-2) + ":" 
    + ("00" + date.getMinutes()).slice(-2) 
    + ":" + ("00" + date.getSeconds()).slice(-2);
}
</script>