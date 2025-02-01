<template>
  <div class="d-flex flex-wrap vw-100 justify-content-center p-2 bg-primary" style="min-height: 100vh;">
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
    </div>
    <!-- Other data -->
    <div class="col-12 col-lg-3 pe-2">
      <div class="col-12 d-flex justify-content-center border-dark text-white mt-2 mt-lg-0">
        <h2>Realtime</h2>
      </div>
      <device-description :device="device" class="mt-2"/> 
      <coordinate-description :coordinate="currentPosition" class="mt-2"/>
      <nuxt-link :to="'/device/' + route.params.id + '/history/'" class="col-12 d-flex justify-content-center btn btn-block btn-info border-dark text-white mt-4">
        <h4>Go to history</h4>
      </nuxt-link>
    </div>
  </div>
</template>
<script setup>
useHead({ title: 'Realtime' });

const config = useRuntimeConfig();
const route = useRoute();
const { $socket } = useNuxtApp();

const device = ref({});

const { data: device_data } = await useAsyncData('device', () => $fetch(config.public.server + '/api/devices/' + route.params.id, { pageSize: 100 }));
device.value = device_data.value;

const coordinates = ref([]);
const currentPosition = computed(() => coordinates.value.at(-1) ?? { x: 0, y: 0, altitude: 0, pressure: 0, temperature: 0, timestamp: '' })

const { data: coordinates_data } = await useAsyncData('coordinates', function () {
  return $fetch(config.public.server + '/api/coordinates/latest', {
    query: { device_id: route.params.id },
  });
});

if (coordinates.value)
  coordinates.value.push(coordinates_data.value);

onMounted(() => { $socket.on("coordinates.device." + route.params.id, (result) => coordinates.value.push(result)); });
onBeforeUnmount(() => $socket.off("coordinates.device." + route.params.id));

const rawCoordinates = computed(() => coordinates.value.map(coordinate => [coordinate.x, coordinate.y]));
</script>