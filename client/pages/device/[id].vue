<template>
  <div class="d-flex vw-100 vh-100 justify-content-center p-2 bg-primary">
    <!-- Map -->
    <div class="col-9 pe-3">
      <LMap
        :zoom="15"
        :center="[current_position.x, current_position.y]"
        :use-global-leaflet="false"
      >
        <LTileLayer
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          layer-type="base"
          name="OpenStreetMap"
        />
        <LMarker :lat-lng="[current_position.x, current_position.y]"/>
        <LPolyline v-if="rawCoordinates.length > 1" :lat-lngs="rawCoordinates" color="red" />
      </LMap>
    </div>
    <div class="col-3 pe-2">
      <div class="card bg-info border-dark">
        <div class="card-body">
          <div class="card-title d-flex justify-content-between">
            <h3 class="text-white">Device</h3>
            <nuxt-link to="/" class="btn btn-primary">All devices</nuxt-link>
          </div>
          <div class="list-group">
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">ID</span>
              <span>{{ device.id }}</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">Name</span>
              <span>{{ device.name }}</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">IMEI</span>
              <span>{{ device.imei }}</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">Part number</span>
              <span v-if="typeof device.part_number === 'string'">{{ device.part_number }}</span>
              <span v-else class="fst-italic">Not defined</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">Serial number</span>
              <span v-if="typeof device.serial_number === 'string'">{{ device.serial_number }}</span>
              <span v-else class="fst-italic">Not defined</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">Manufacturer</span>
              <span v-if="typeof device.manufacturer === 'string'">{{ device.manufacturer }}</span>
              <span v-else class="fst-italic">Not defined</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">Model</span>
              <span v-if="typeof device.model === 'string'">{{ device.model }}</span>
              <span v-else class="fst-italic">Not defined</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">Revision</span>
              <span v-if="typeof device.revision === 'string'">{{ device.revision }}</span>
              <span v-else class="fst-italic">Not defined</span>
            </div>
          </div>
        </div>
      </div>
      <div class="card mt-2 bg-info border-dark">
        <div class="card-body">
          <h3 class="card-title text-white">Current position</h3>
          <div class="list-group">
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">X</span>
              <span>{{ current_position.x.toFixed(4) }}</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">Y</span>
              <span>{{ current_position.y.toFixed(4) }}</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">Altitude</span>
              <span v-if="typeof current_position.altitude === 'number'">{{ current_position.altitude.toFixed(2) }} meters</span>
              <span v-else class="fst-italic">Not defined</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">Pressure</span>
              <span v-if="typeof current_position.pressure === 'number'">{{ current_position.pressure.toFixed(2) }} atm</span>
              <span v-else class="fst-italic">Not defined</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">Temperature</span>
              <span v-if="typeof current_position.temperature === 'number'">{{ current_position.temperature.toFixed(2) }} °C</span>
              <span v-else class="fst-italic">Not defined</span>
            </div>
            <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
              <span class="fw-bold">Last update</span>
              <span>{{ formatDate(current_position.timestamp) }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
<script setup>
const config = useRuntimeConfig();
const route = useRoute();
const { $socket } = useNuxtApp();

const device = ref({});

const { data: device_data } = await useAsyncData('device', () => $fetch(config.public.server + '/api/devices/' + route.params.id, { pageSize: 100 }));
device.value = device_data.value;

const coordinates = ref([]);
const current_position = computed(() => coordinates.value.at(-1) ?? { x: 0, y: 0, altitude: 0, pressure: 0, temperature: 0, timestamp: new Date() })

const { data: coordinates_data } = await useAsyncData('coordinates', function () {
  return $fetch(config.public.server + '/api/coordinates/', {
    query: { device_id: route.params.id },
    pageSize: 1,
    sort: '-timestamp'
  });
});

coordinates.value = coordinates_data.value.rows;

onMounted(() => { $socket.on("coordinates.device." + route.params.id, (result) => coordinates.value.push(result)); });
onBeforeUnmount(() => $socket.off("coordinates.device." + route.params.id));

const rawCoordinates = computed(() => coordinates.value.map(coordinate => [coordinate.x, coordinate.y]));

function formatDate (_date) {
  const date = new Date(_date);

  return ("00" + date.getDate()).slice(-2)
    + "/" + ("00" + (date.getMonth() + 1)).slice(-2) 
    + "/" + date.getFullYear() + " " 
    + ("00" + date.getHours()).slice(-2) + ":" 
    + ("00" + date.getMinutes()).slice(-2) 
    + ":" + ("00" + date.getSeconds()).slice(-2);
}

</script>