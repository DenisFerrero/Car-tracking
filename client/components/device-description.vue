<template>
  <div class="card bg-info border-dark">
    <div class="card-body">
      <div class="card-title d-flex justify-content-between">
        <h3 class="text-white">Device</h3>
        <nuxt-link to="/" class="btn btn-primary">All devices</nuxt-link>
      </div>
      <div class="list-group">
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">ID</span>
          <span>{{ props.device.id }}</span>
        </div>
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">Name</span>
          <span>{{ props.device.name }}</span>
        </div>
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">IMEI</span>
          <span>{{ props.device.imei }}</span>
        </div>
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">Manufacturer</span>
          <span v-if="typeof props.device.manufacturer === 'string'">{{ props.device.manufacturer }}</span>
          <span v-else class="fst-italic">Not defined</span>
        </div>
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">Model</span>
          <span v-if="typeof props.device.model === 'string'">{{ props.device.model }}</span>
          <span v-else class="fst-italic">Not defined</span>
        </div>
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">Revision</span>
          <span v-if="typeof props.device.revision === 'string'">{{ props.device.revision }}</span>
          <span v-else class="fst-italic">Not defined</span>
        </div>
      </div>
    </div>
  </div>
</template>
<script setup>
const props = defineProps({
  device: {
    type: Object,
    default: () => {}
  }
})
</script>