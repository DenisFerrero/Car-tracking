<template>
  <div class="d-flex flex-wrap col-12 justify-content-center p-2 bg-primary">
    <div class="col-12 d-flex justify-content-center border-dark text-white">
      <h2>History</h2>
    </div>
    <!-- Map -->
    <div v-if="currentCoordinate !== null" class="col-11 col-lg-9 pe-lg-3">
      <div class="map">
        <LMap
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
          <LPolyline v-if="rawCoordinates.length > 1" :lat-lngs="rawCoordinates" color="red" />
        </LMap>
      </div>
      <div class="col-12 d-flex flex-wrap justify-content-center align-items-center mt-2">
        <div class="btn-group me-2" role="group">
          <button type="button" class="btn btn-lg btn-secondary border-dark" @click="click_Play">Play</button>
          <button type="button" class="btn btn-lg btn-secondary border-dark" @click="click_Pause">Pause</button>
          <button type="button" class="btn btn-lg btn-secondary border-dark" @click="click_Stop">Stop</button>
        </div>
        <div class="col-10 col-lg-2 mt-2 mt-lg-0">
          <div class="input-group">
            <input v-model="stepTimeout" type="number" class="form-control" :disabled="timeoutId !== undefined" placeholder="Step timeout">
            <span class="input-group-text">ms</span>
          </div>
        </div>
      </div>
    </div>
    <div v-else class="col-11 col-lg-9 pe-lg-3 d-flex justify-content-center align-items-center display-5 text-white">
      Cannot load the map without any coordinates
    </div>
    <!-- Other data -->
    <div class="col-12 col-lg-3 pe-lg-2">
      <div class="card bg-info border-dark mt-2 mt-lg-0">
        <div class="card-body">
          <div class="card-title">
            <h3 class="text-white">Filters</h3>
          </div>
          <vue-date-picker v-model="dates" :range="true" :format="formatPicker" :multi-calendars="true"/>
          <button class="btn btn-secondary col-12 mt-2" @click="loadCoordinates">Search</button>
        </div>
      </div>
      <device-description :device="device" class="mt-2"/> 
      <coordinate-description v-if="coordinates.length > 0" :coordinate="currentCoordinate" class="mt-2" />
      <nuxt-link :to="'/device/' + route.params.id + '/realtime/'" class="col-12 d-flex justify-content-center btn btn-block btn-info border-dark text-white mt-4">
        <h4>Go to realtime</h4>
      </nuxt-link>
    </div>
    <!-- Graphs -->
    <div v-if="coordinates.length > 0" class="d-flex flex-wrap col-12 mt-2">
      <client-only>
        <div class="col-12 mt-2 d-flex justify-content-center border-dark text-white">
          <h3>Graphs</h3>
        </div>
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
</template>
<script setup>
useHead({ title: 'Car tracking - History' });

const config = useRuntimeConfig();
const route = useRoute();
const { $socket } = useNuxtApp();

const device = ref({});
const coordinates = ref([]);
const currentCoordinate = ref(null);

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

const rawCoordinates = ref([]);

async function loadCoordinates () {
  const params = {
    query: { device_id: route.params.id },
    start: new Date(dates.value[0]).toISOString(), end: new Date(dates.value[1]).toISOString(),
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
  // If the raw coordinates are already completely fill, empty it to start again
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

// #endregion

// #region Graphs

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

if (import.meta.client) {
  const style = getComputedStyle(document.documentElement);

  altitudeChartOptions.value = {
    chart: {
      type: "area",
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
    },
    chart: {
      background: style.getPropertyValue('--bs-secondary')
    },
    colors: [style.getPropertyValue('--bs-dark')],
    series: altitudeSeries,
  };

  pressureChartOptions.value = {
    chart: {
      type: "area",
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
    tooltip: {
      x: {
        format: "yyyy-MM-dd HH:mm:ss", // Display full timestamp
      },
      y: {
        formatter: (value) => `${value} atmosphere`, // Format altitude in tooltip
      }
    },
    chart: {
      background: style.getPropertyValue('--bs-secondary')
    },
    colors: [style.getPropertyValue('--bs-dark')],
    series: pressureSeries,
  };

  temperatureChartOptions.value = {
    chart: {
      type: "area",
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
    tooltip: {
      x: {
        format: "yyyy-MM-dd HH:mm:ss", // Display full timestamp
      },
      y: {
        formatter: (value) => `${value} °C`, // Format altitude in tooltip
      }
    },
    chart: {
      background: style.getPropertyValue('--bs-secondary')
    },
    colors: [style.getPropertyValue('--bs-dark')],
    series: altitudeSeries,
  };
}

// #endregion
</script>