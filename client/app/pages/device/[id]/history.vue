<template>
  <div class="min-h-screen flex flex-col transition-colors duration-300" style="background: var(--bg-gradient)">
    <Navbar />
    
    <div class="flex-grow container mx-auto px-4 py-8">
      <!-- Page Header -->
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-6 gap-2">
        <h2 class="text-2xl font-bold text-title flex items-center gap-2 m-0">
          <span class="text-xl">📊</span> {{ t('historyTitle') }}
          <span v-if="device?.name" class="px-2.5 py-0.5 rounded bg-badge-bg text-badge-text border border-card-border/50 text-[10px] font-mono tracking-widest uppercase ml-3">
            {{ device.name }}
          </span>
        </h2>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        <!-- Left: Map & Replay controls -->
        <div class="lg:col-span-2 xl:col-span-3 flex flex-col gap-4">
          <div v-if="currentCoordinate !== null" class="flex flex-col gap-4">
            <div class="h-[56vh] lg:h-[70vh] rounded-2xl border border-map-border shadow-card overflow-hidden relative">
              <LMap
                class="map h-full w-full"
                :zoom="15"
                :center="[currentCoordinate.x, currentCoordinate.y]"
                :use-global-leaflet="false"
              >
                <LTileLayer
                  url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                  layer-type="base"
                  name="OpenStreetMap"
                />
                <LMarker :lat-lng="[currentCoordinate.x, currentCoordinate.y]"/>
                <LPolyline v-if="rawCoordinates.length > 1" :lat-lngs="rawCoordinates" color="#6366f1" :weight="4" />
              </LMap>
            </div>

            <!-- Playback controls -->
            <div class="glass-panel border-0 p-4 sm:p-5 flex flex-wrap justify-between items-center gap-4">
              <div class="flex shadow-sm rounded-xl overflow-hidden" role="group">
                <button type="button" class="px-5 py-2.5 bg-btn-sec-bg border-r border-btn-sec-border/40 hover:bg-btn-sec-hover text-btn-sec-text text-sm font-semibold transition cursor-pointer flex items-center gap-1.5" @click="click_Play">
                  <span>▶️</span> {{ t('play') }}
                </button>
                <button type="button" class="px-5 py-2.5 bg-btn-sec-bg border-r border-btn-sec-border/40 hover:bg-btn-sec-hover text-btn-sec-text text-sm font-semibold transition cursor-pointer flex items-center gap-1.5" @click="click_Pause">
                  <span>⏸️</span> {{ t('pause') }}
                </button>
                <button type="button" class="px-5 py-2.5 bg-btn-sec-bg hover:bg-btn-sec-hover text-btn-sec-text text-sm font-semibold transition cursor-pointer flex items-center gap-1.5" @click="click_Stop">
                  <span>⏹️</span> {{ t('stop') }}
                </button>
              </div>

              <div class="flex items-center gap-3">
                <span class="text-xs font-bold text-text-muted tracking-wide uppercase">{{ t('stepTimeout') }}</span>
                <div class="flex rounded-lg overflow-hidden border border-input-border bg-input-bg max-w-[160px]">
                  <input v-model="stepTimeout" type="number" class="w-20 px-3 py-2 bg-transparent text-center text-sm text-body-text focus:outline-none" :disabled="timeoutId !== undefined" placeholder="500">
                  <span class="px-3 py-2 bg-card-bg/20 border-l border-input-border text-text-muted text-xs font-semibold flex items-center select-none">{{ t('msUnit') }}</span>
                </div>
              </div>
            </div>
          </div>

          <div v-else class="glass-panel flex flex-col items-center justify-center text-center p-8 min-h-[50vh]">
            <span class="text-6xl mb-4">📡</span>
            <h4 class="text-lg font-bold text-title">{{ t('noCoordinates') }}</h4>
          </div>
        </div>

        <!-- Right: Filters & Details -->
        <div class="flex flex-col gap-4">
          <!-- Filters Card -->
          <div class="glass-panel p-5 flex flex-col">
            <h4 class="text-base font-bold text-title flex items-center mb-4 m-0">
              <span class="mr-2">🔍</span> {{ t('filters') }}
            </h4>
            <div class="mb-4">
              <vue-date-picker 
                v-model="dates" 
                :range="true" 
                :format="formatPicker" 
                :multi-calendars="true"
                :dark="theme === 'dark'"
              />
            </div>
            <button class="w-full py-2.5 rounded-lg text-sm font-semibold bg-gradient-to-br from-indigo-500 to-indigo-600 hover:from-indigo-600 hover:to-indigo-700 text-white shadow-md hover:shadow-lg transition duration-200 cursor-pointer flex items-center justify-center gap-2" @click="loadCoordinates">
              <span>⚡</span> {{ t('search') }}
            </button>
          </div>

          <device-description :device="device" /> 
          <coordinate-description v-if="coordinates.length > 0 && currentCoordinate" :coordinate="currentCoordinate" />

          <nuxt-link :to="'/device/' + route.params.id + '/realtime/'" class="w-full py-3.5 mt-2 rounded-xl text-sm font-bold bg-gradient-to-br from-cyan-500 to-cyan-600 hover:from-cyan-600 hover:to-cyan-700 text-white shadow-md hover:shadow-lg flex items-center justify-center gap-2 transition duration-200 cursor-pointer border border-cyan-500/20">
            <span>⚡</span> {{ t('goToRealtime') }}
          </nuxt-link>
        </div>
      </div>

      <!-- Graphs Section -->
      <div v-if="coordinates.length > 0" class="mt-12 w-full">
        <div class="text-center mb-8">
          <h3 class="text-3xl font-extrabold tracking-tight tracking-title text-title mb-2">📈 {{ t('graphs') }}</h3>
          <p class="text-text-muted">{{ t('graphsSubtitle') }}</p>
        </div>
        
        <client-only>
          <div class="grid grid-cols-1 xl:grid-cols-3 gap-6 w-full">
            <div class="glass-panel p-5 border-0 h-full">
              <ApexChart type="line" :options="altitudeChartOptions" :series="altitudeSeries" />
            </div>
            <div class="glass-panel p-5 border-0 h-full">
              <ApexChart type="line" :options="pressureChartOptions" :series="pressureSeries" />
            </div>
            <div class="glass-panel p-5 border-0 h-full">
              <ApexChart type="line" :options="temperatureChartOptions" :series="temperatureSeries" />
            </div>
          </div>
        </client-only>
      </div>
    </div>
  </div>
</template>

<script setup>
import { useI18n } from '~/composables/useI18n'
import { useTheme } from '~/composables/useTheme'
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue'

const { locale, t } = useI18n()
const { theme } = useTheme()

useHead({ title: 'Car tracking - History' });

const config = useRuntimeConfig();
const route = useRoute();
const router = useRouter();
const { $socket } = useNuxtApp();

const device = ref({});
const coordinates = ref([]);
const currentCoordinate = ref(null);

const { data: device_data } = await useAsyncData('device', () => $fetch(config.public.server + '/api/devices/' + route.params.id, { pageSize: 100 }));
device.value = device_data.value;

let startDate = new Date().setHours(0, 0, 0, 0);
if (route.query.start) {
  startDate = new Date(route.query.start);
}

let endDate = new Date();
if (route.query.end) {
  endDate = new Date(route.query.end);
}

const dates = ref([startDate, endDate]);

function formatPicker (dates) {
  const d1 = formatDate(dates[0]);
  const d2 = formatDate(dates[1]);

  return d1 + ' / ' + d2;
}

function formatDate (_date) {
  const date = new Date(_date);

  return ("00" + date.getDate()).slice(-2)
    + "/" + ("00" + (date.getMonth() + 1)).slice(-2) 
    + "/" + date.getFullYear() + " " 
    + ("00" + date.getHours()).slice(-2) + ":" 
    + ("00" + date.getMinutes()).slice(-2) 
    + ":" + ("00" + date.getSeconds()).slice(-2);
}

onMounted(loadCoordinates);

const rawCoordinates = ref([]);

async function loadCoordinates () {
  const start = new Date(dates.value[0]).toISOString();
  const end = new Date(dates.value[1]).toISOString();

  router.push({ query: { start, end } });

  const params = {
    query: { device_id: route.params.id }, start, end,
    sort: 'timestamp', pageSize: 100, page: 1
  };
  const results = await $socket.syncEmit('call', 'coordinates.list', params);
  let pResults = [];

  if (results.totalPages > 0) {
    const promises = [];
    for (let i = 2; i <= results.totalPages; i++) {
      promises.push($socket.syncEmit('call', 'coordinates.list', Object.assign({}, params, { page: i })));
    }
    pResults = await Promise.all(promises);
  }

  coordinates.value = results.rows.concat(...pResults.map(p => p.rows));
  if (coordinates.value.length > 0) {
    currentCoordinate.value = coordinates.value.at(-1);
  }

  rawCoordinates.value = coordinates.value.map(coordinate => [coordinate.x, coordinate.y]);
}

// #region Replay

const timeoutId = ref(undefined);
const stepTimeout = ref(500);

async function stepCoordinate () {
  const index = rawCoordinates.value.length;
  const coordinate = coordinates.value[index]; 

  if (coordinate !== undefined) {
    rawCoordinates.value = [...rawCoordinates.value, [coordinate.x, coordinate.y]];
    currentCoordinate.value = coordinate;

    timeoutId.value = setTimeout(stepCoordinate, stepTimeout.value);
  } else {
    timeoutId.value = undefined;
  }
}

function click_Play () {
  if (rawCoordinates.value.length === coordinates.value.length) {
    rawCoordinates.value = [];
  }
  stepCoordinate();
}

function click_Pause () {
  if (timeoutId.value !== undefined) {
    clearTimeout(timeoutId.value);
    timeoutId.value = undefined;
  }
}

function click_Stop () {
  if (timeoutId.value !== undefined) {
    clearTimeout(timeoutId.value);
    timeoutId.value = undefined;
  }

  rawCoordinates.value = coordinates.value.map(coordinate => [coordinate.x, coordinate.y]);
  currentCoordinate.value = coordinates.value.at(-1);
}

onBeforeUnmount(() => {
  if (timeoutId.value !== undefined) {
    clearTimeout(timeoutId.value);
    timeoutId.value = undefined;
  }
});

// #endregion

// #region Graphs

const altitudeChartOptions = ref({});
const altitudeSeries = computed(function () {
  return [{
    name: t('altitude') + ' (m)',
    data: coordinates.value.map(c => ({ x: new Date(c.timestamp).getTime(), y: c.altitude }))
  }];
});

const pressureChartOptions = ref({});
const pressureSeries = computed(function () {
  return [{
    name: t('pressure') + ' (atm)',
    data: coordinates.value.map(c => ({ x: new Date(c.timestamp).getTime(), y: c.pressure }))
  }];
});

const temperatureChartOptions = ref({});
const temperatureSeries = computed(function () {
  return [{
    name: t('temperature') + ' (°C)',
    data: coordinates.value.map(c => ({ x: new Date(c.timestamp).getTime(), y: c.temperature }))
  }];
});

function getChartThemeMode() {
  return theme.value === 'dark' ? 'dark' : 'light';
}

function buildChartOptions(titleText, yAxisTitle, colorGlow) {
  return {
    chart: {
      type: "area",
      height: 350,
      background: "transparent",
      zoom: { type: "x", enabled: true },
      toolbar: { autoSelected: "zoom", tools: { zoom: true, pan: true, reset: true } },
    },
    stroke: {
      curve: 'smooth',
      width: 3,
    },
    fill: {
      type: 'gradient',
      gradient: {
        shadeIntensity: 1,
        opacityFrom: 0.45,
        opacityTo: 0.05,
        stops: [0, 100]
      }
    },
    title: { text: titleText, align: "center", style: { fontSize: '15px', fontWeight: 600, color: 'var(--title-color)' } },
    xaxis: { type: "datetime", title: { text: t('time'), style: { color: 'var(--text-muted)' } }, labels: { style: { colors: 'var(--text-muted)' } } },
    yaxis: { title: { text: yAxisTitle, style: { color: 'var(--text-muted)' } }, labels: { style: { colors: 'var(--text-muted)' } } },
    theme: { mode: getChartThemeMode(), palette: 'palette1' },
    tooltip: { x: { format: "yyyy-MM-dd HH:mm:ss" } },
    colors: [colorGlow],
    grid: { borderColor: 'rgba(99, 102, 241, 0.08)' }
  };
}

const buildAllChartOptions = () => {
  altitudeChartOptions.value = buildChartOptions(t('altitude'), "m", "#6366f1");
  pressureChartOptions.value = buildChartOptions(t('pressure'), "atm", "#06b6d4");
  temperatureChartOptions.value = buildChartOptions(t('temperature'), "°C", "#10b981");
};

if (import.meta.client) {
  buildAllChartOptions();
  watch([theme, () => locale.value], () => {
    buildAllChartOptions();
  });
}

// #endregion
</script>

<style scoped>
.tracking-title {
  background: linear-gradient(135deg, var(--title-color) 30%, #a5b4fc 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}
</style>