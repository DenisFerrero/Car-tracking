<template>
  <div class="d-flex flex-wrap vw-100 justify-content-center p-2 bg-primary">
    <div class="col-12 d-flex justify-content-center border-dark text-white">
      <h2>Realtime</h2>
    </div>
    <!-- Map -->
    <div v-if="currentPosition !== null" class="col-11 col-lg-9 pe-lg-3 map" >
      <LMap
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
        <LPolyline v-if="rawCoordinates.length > 1" :lat-lngs="rawCoordinates" color="red" />
      </LMap>
    </div>
    <div v-else class="col-11 col-lg-9 pe-lg-3 d-flex justify-content-center align-items-center display-5 text-white">
      Cannot load the map without any coordinates
    </div>
    <!-- Other data -->
    <div class="col-12 col-lg-3 pe-lg-2">
      <device-description :device="device" class="mt-2 mt-lg-0"/> 
      <coordinate-description v-if="currentPosition !== null" :coordinate="currentPosition" class="mt-2" />
      <nuxt-link :to="'/device/' + route.params.id + '/history/'" class="col-12 d-flex justify-content-center btn btn-block btn-info border-dark text-white mt-4">
        <h4>Go to history</h4>
      </nuxt-link>
    </div>
  </div>
</template>
<script setup>
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