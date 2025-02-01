<template>
  <div class="d-flex flex-wrap col-12 justify-content-center p-2 bg-primary" style="min-height: 100vh;">
    <!-- Map -->
    <div class="col-11 col-lg-9 pe-lg-3">
      <LMap
        :zoom="15"
        style="height: 96vh"
        :center="[currentPosition.x, currentPosition.y]"
        :use-global-leaflet="false"
      >
        <LTileLayer
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          layer-type="base"
          name="OpenStreetMap"
        />
        <LMarker :lat-lng="[currentPosition.x, currentPosition.y]"/>
        <LPolyline v-if="rawCoordinates.length > 1" :lat-lngs="rawCoordinates" color="red" />
      </LMap>
      <!-- Graphs -->
      <div v-if="coordinates.length > 0" class="d-flex flex-wrap col-12 mt-2">
        <client-only>
          <div class="col-12 col-lg-4 pe-1">
            <ApexChart type="line" :options="altitudeChartOptions" :series="altitudeSeries" />
          </div>
          <div class="col-12 col-lg-4 pe-1">
            <ApexChart type="line" :options="pressureChartOptions" :series="pressureSeries" />
          </div>
          <div class="col-12 col-lg-4">
            <ApexChart type="line" :options="temperatureChartOptions" :series="temperatureSeries" />
          </div>
        </client-only>
      </div>
    </div>
    <!-- Other data -->
    <div class="col-12 col-lg-3 pe-2">
      <div class="col-12 d-flex justify-content-center border-dark text-white mt-2 mt-lg-0">
        <h2>History</h2>
      </div>
      <div class="card bg-info border-dark mt-2">
        <div class="card-body">
          <div class="card-title">
            <h3 class="text-white">Filters</h3>
          </div>
          <vue-date-picker v-model="dates" :range="true" :format="formatPicker" :multi-calendars="true"/>
          <button class="btn btn-secondary col-12 mt-2" @click="loadCoordinates">Search</button>
        </div>
      </div>
      <device-description :device="device" class="mt-2"/> 
      <coordinate-description v-if="coordinates.length > 0" :coordinate="currentPosition" class="mt-2" />
      <nuxt-link :to="'/device/' + route.params.id + '/realtime/'" class="col-12 d-flex justify-content-center btn btn-block btn-info border-dark text-white mt-4">
        <h4>Go to realtime</h4>
      </nuxt-link>
    </div>
  </div>
</template>
<script setup>
useHead({ title: 'History' });

const config = useRuntimeConfig();
const route = useRoute();
const { $socket } = useNuxtApp();

const device = ref({});
const coordinates = ref([]);
const currentPosition = ref({ x: 0, y: 0, altitude: 0, pressure: 0, temperature: 0, timestamp: '' })

const { data: device_data } = await useAsyncData('device', () => $fetch(config.public.server + '/api/devices/' + route.params.id, { pageSize: 100 }));
device.value = device_data.value;

const dates = ref([new Date().setHours(0, 0, 0, 0), new Date()]);

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

async function loadCoordinates () {
  const params = {
    query: { device_id: route.params.id },
    start: new Date(dates.value[0]).toISOString(), end: new Date(dates.value[1]).toISOString(),
    sort: 'timestamp', pageSize: 100, page: 1
  };
  console.log('Request #1');
  const results = await $socket.syncEmit('call', 'coordinates.list', params);
  let pResults = [];

  if (results.totalPages > 0) {
    const promises = [];
    for (let i = 1; i < results.totalPages; i++) {
      console.log('Request #' + i);
      promises.push($socket.syncEmit('call', 'coordinates.list', Object.assign({}, params, { page: i })));
    }
    pResults = await Promise.all(promises);
  }

  coordinates.value = results.rows.concat(...pResults.map(p => p.rows));
  currentPosition.value = coordinates.value.at(-1);
}

const rawCoordinates = computed(() => coordinates.value.map(coordinate => [coordinate.x, coordinate.y]));

const altitudeChartOptions = ref({});
const altitudeSeries = computed(function () {
  return [{
    name: 'Altitude (meters)',
    data: coordinates.value.map(c => ({ x: new Date(c.timestamp).getTime(), y: c.altitude }))
  }];
});

const pressureChartOptions = ref({});
const pressureSeries = computed(function () {
  return [{
    name: 'Pressure (atm)',
    data: coordinates.value.map(c => ({ x: new Date(c.timestamp).getTime(), y: c.pressure }))
  }];
});

const temperatureChartOptions = ref({});
const temperatureSeries = computed(function () {
  return [{
    name: 'Temperature (°C)',
    data: coordinates.value.map(c => ({ x: new Date(c.timestamp).getTime(), y: c.temperature }))
  }];
});

function dataPointSelection (event, chartContext, config) {
  const index = config.dataPointIndex;
  currentPosition.value = coordinates.value[index];
}

if (import.meta.client) {
  const style = getComputedStyle(document.documentElement);

  altitudeChartOptions.value = {
    chart: {
      type: "line",
      events: { dataPointSelection },
      height: 350,
      zoom: {
        type: "x", // Enable horizontal zooming
        enabled: true,
      },
      toolbar: {
        autoSelected: "zoom", // Default to zoom tool
        tools: {
          zoom: true,
          pan: true,
          reset: true,
        },
      },
    },
    title: {
      text: "Altitude",
      align: "center",
    },
    xaxis: {
      type: "datetime", // x-axis is based on time
      title: {
        text: "Time",
      }
    },
    yaxis: {
      title: {
        text: "Altitude (meters)",
      }
    },
    markers: { size: 5 },
    theme: {
      mode: 'dark', // light or dark
      palette: 'palette1', // Choose a predefined palette
    },
    tooltip: {
      x: {
        format: "yyyy-MM-dd HH:mm:ss", // Display full timestamp
      },
      y: {
        formatter: (value) => `${value} meters`, // Format altitude in tooltip
      },
      intersect: true,
      shared: false
    },
    chart: {
      background: style.getPropertyValue('--bs-secondary')
    },
    colors: [style.getPropertyValue('--bs-dark')],
    series: altitudeSeries,
  };

  pressureChartOptions.value = {
    chart: {
      type: "line",
      events: { dataPointSelection },
      height: 350,
      zoom: {
        type: "x", // Enable horizontal zooming
        enabled: true,
      },
      toolbar: {
        autoSelected: "zoom", // Default to zoom tool
        tools: {
          zoom: true,
          pan: true,
          reset: true,
        },
      },
    },
    title: {
      text: "Pressure",
      align: "center",
    },
    xaxis: {
      type: "datetime", // x-axis is based on time
      title: {
        text: "Time",
      }
    },
    yaxis: {
      title: {
        text: "Pressure (atm)",
      }
    },
    theme: {
      mode: 'dark', // light or dark
      palette: 'palette1', // Choose a predefined palette
    },
    markers: { size: 5 },
    tooltip: {
      x: {
        format: "yyyy-MM-dd HH:mm:ss", // Display full timestamp
      },
      y: {
        formatter: (value) => `${value} atmosphere`, // Format altitude in tooltip
      },
      intersect: true,
      shared: false
    },
    chart: {
      background: style.getPropertyValue('--bs-secondary')
    },
    colors: [style.getPropertyValue('--bs-dark')],
    series: pressureSeries,
  };

  temperatureChartOptions.value = {
    chart: {
      type: "line",
      events: { dataPointSelection },
      height: 350,
      zoom: {
        type: "x", // Enable horizontal zooming
        enabled: true,
      },
      toolbar: {
        autoSelected: "zoom", // Default to zoom tool
        tools: {
          zoom: true,
          pan: true,
          reset: true,
        },
      },
    },
    title: {
      text: "Temperature",
      align: "center",
    },
    xaxis: {
      type: "datetime", // x-axis is based on time
      title: {
        text: "Time",
      }
    },
    yaxis: {
      title: {
        text: "Temperature (°C)",
      }
    },
    theme: {
      mode: 'dark', // light or dark
      palette: 'palette1', // Choose a predefined palette
    },
    markers: { size: 5 },
    tooltip: {
      x: {
        format: "yyyy-MM-dd HH:mm:ss", // Display full timestamp
      },
      y: {
        formatter: (value) => `${value} °C`, // Format altitude in tooltip
      },
      intersect: true,
      shared: false
    },
    chart: {
      background: style.getPropertyValue('--bs-secondary')
    },
    colors: [style.getPropertyValue('--bs-dark')],
    series: altitudeSeries,
  };
}
</script>