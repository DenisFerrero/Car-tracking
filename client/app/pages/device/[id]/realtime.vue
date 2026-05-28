<template>
  <div class="min-h-screen flex flex-col transition-colors duration-300" style="background: var(--bg-gradient)">
    <Navbar />
    
    <div class="flex-grow container mx-auto px-4 py-8">
      <!-- Page Header -->
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-6 gap-2">
        <h2 class="text-2xl font-bold text-title flex items-center gap-2 m-0">
          <span class="text-xl">⚡</span> {{ t('realtimeTitle') }}
          <span v-if="device?.name" class="px-2.5 py-0.5 rounded bg-badge-bg text-badge-text border border-card-border/50 text-[10px] font-mono tracking-widest uppercase ml-3">
            {{ device.name }}
          </span>
        </h2>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        <!-- Map Container -->
        <div class="lg:col-span-2 xl:col-span-3 flex flex-col">
          <div v-if="currentPosition !== null" class="h-[56vh] lg:h-[72vh] rounded-2xl border border-map-border shadow-card overflow-hidden relative">
            <LMap
              class="map h-full w-full"
              :zoom="15"
              :center="[currentPosition.x, currentPosition.y]"
              :use-global-leaflet="false"
            >
              <LTileLayer
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                layer-type="base"
                name="OpenStreetMap"
              />
              <LMarker :lat-lng="[currentPosition.x, currentPosition.y]"/>
              <LPolyline v-if="rawCoordinates.length > 1" :lat-lngs="rawCoordinates" color="#6366f1" :weight="4" />
            </LMap>
          </div>
          <div v-else class="glass-panel flex flex-col items-center justify-center text-center p-8 min-h-[50vh]">
            <span class="text-6xl mb-4">📡</span>
            <h4 class="text-lg font-bold text-title">{{ t('noCoordinates') }}</h4>
          </div>
        </div>

        <!-- Telemetry information details -->
        <div class="flex flex-col gap-4">
          <device-description :device="device" /> 
          <coordinate-description v-if="currentPosition !== null" :coordinate="currentPosition" />
          
          <nuxt-link :to="'/device/' + route.params.id + '/history/'" class="w-full py-3.5 mt-2 rounded-xl text-sm font-bold bg-gradient-to-br from-cyan-500 to-cyan-600 hover:from-cyan-600 hover:to-cyan-700 text-white shadow-md hover:shadow-lg flex items-center justify-center gap-2 transition duration-200 cursor-pointer border border-cyan-500/20">
            <span>📅</span> {{ t('goToHistory') }}
          </nuxt-link>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { useI18n } from '~/composables/useI18n'
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'

const { t } = useI18n()

useHead({ title: 'Car tracking - Realtime' });

const config = useRuntimeConfig();
const route = useRoute();
const { $socket } = useNuxtApp();

const device = ref({});

const { data: device_data } = await useAsyncData('device', () => $fetch(config.public.server + '/api/devices/' + route.params.id, { pageSize: 100 }));
device.value = device_data.value;

const coordinates = ref([]);
const currentPosition = computed(() => coordinates.value.length > 0 ? coordinates.value.at(-1) : null);

const { data: coordinates_data } = await useAsyncData('coordinates', function () {
  return $fetch(config.public.server + '/api/coordinates/latest', {
    query: { device_id: route.params.id },
  });
});

if (typeof coordinates_data.value?.x === 'number' && typeof coordinates_data.value?.y === 'number')
  coordinates.value.push(coordinates_data.value);

onMounted(() => { $socket.on("coordinates.device." + route.params.id, (result) => coordinates.value.push(result)); });
onBeforeUnmount(() => $socket.off("coordinates.device." + route.params.id));

const rawCoordinates = computed(() => coordinates.value.map(coordinate => [coordinate.x, coordinate.y]));
</script>