<template>
  <div class="d-flex vw-100 vh-100 align-items-center justify-content-center bg-primary">
    <div v-if="results?.total > 0" class="col-5">
      <div class="card bg-secondary border-dark">
        <div class="card-body">
          <h5 class="card-title text-center text-white">
            Devices
          </h5>
          <div class="list-group">
            <nuxt-link v-for="row in results.rows" :key="row.id" :to="`/device/${row.id}`">
              <div class="list-group-item list-group-item-action text-white bg-info border-dark">
                {{ row.name }}
              </div>
            </nuxt-link>
          </div>
        </div>
      </div>
    </div>
    <div v-else class="text-white">
      Cannot find any device, start transmitting!
    </div>
  </div>
</template>

<script setup>

const config = useRuntimeConfig();
const results = ref({});

const { data } = await useAsyncData('devices', () => $fetch(config.public.server + '/api/devices', { pageSize: 100 }));

results.value = data.value;
const { $socket } = useNuxtApp();

onMounted(() => { $socket.on('devices.changed', refreshList); });
onBeforeUnmount(() => { $socket.off('devices.changed'); })

async function refreshList () {
  results.value = await $socket.syncEmit('call', 'devices.list', { pageSize: 100 });
}

</script>
