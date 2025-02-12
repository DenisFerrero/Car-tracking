<template>
  <div class="d-flex vw-100 vh-100 align-items-center justify-content-center bg-primary">
    <div v-if="results?.total > 0" class="col-11 col-lg-5">
      <div class="card bg-secondary border-dark">
        <div class="card-body">
          <h5 class="card-title text-center text-white">
            Devices
          </h5>
          <div class="list-group">
              <div v-for="row in results.rows" :key="row.id" class="list-group-item list-group-item-action text-white bg-info border-dark d-flex flex-wrap justify-content-between align-items-center">
                <div class="col-12 col-lg-auto text-center">{{ row.name }}</div>
                <div class="col-12 col-lg-auto mt-2 mt-lg-0 d-flex justify-content-between">
                  <button class="btn btn-sm btn-secondary me-2" data-bs-toggle="modal" data-bs-target="#editModal" @click="setDevice(row)">Edit</button>
                  <nuxt-link :to="`/device/${row.id}/realtime`">
                    <button class="btn btn-sm btn-secondary me-2">Realtime</button>
                  </nuxt-link>
                  <nuxt-link :to="`/device/${row.id}/history`">
                    <button class="btn btn-sm btn-secondary">History</button>
                  </nuxt-link>
                </div>
              </div>
          </div>
        </div>
      </div>
    </div>
    <div v-else class="text-white">
      Cannot find any device, start transmitting!
    </div>

    <div id="editModal" class="modal" tabindex="-1">
      <div class="modal-dialog">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title">Edit device</h5>
          </div>
          <div class="modal-body">
            <div class="form-floating">
              <input v-model="editDevice.name" type="text" class="form-control">
              <label for="floatingInputGroup2">Name</label>
            </div>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
            <button type="button" class="btn btn-primary" data-bs-dismiss="modal" @click="saveDevice()">Save changes</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
useHead({ title: 'Devices' });

const config = useRuntimeConfig();
const results = ref({});

const { data } = await useAsyncData('devices', () => $fetch(config.public.server + '/api/devices', { query: { pageSize: 100 } }));

results.value = data.value;
const { $socket } = useNuxtApp();

const editDevice = ref({});

function setDevice (device) {
  editDevice.value = JSON.parse(JSON.stringify(device));
}

function saveDevice () {
  $fetch(config.public.server + '/api/devices/' + editDevice.value.id, {
    method: 'PUT',
    body: { name: editDevice.value.name }
  });
}

onMounted(() => { $socket.on('devices.changed', refreshList); });
onBeforeUnmount(() => { $socket.off('devices.changed'); })

async function refreshList () {
  results.value = await $socket.syncEmit('call', 'devices.list', { pageSize: 100 });
}

</script>
