<template>
  <div class="card bg-info border-dark">
    <div class="card-body">
      <div class="card-title d-flex justify-content-between">
        <h3 class="text-white">Position</h3>
        <a :href="'https://www.google.com/maps/place/' + props.coordinate.x + ',' + props.coordinate.y" class="btn btn-primary" target="_blank">Google</a>
      </div>
      <div class="list-group">
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">X</span>
          <span>{{ props.coordinate.x?.toFixed(4) }}</span>
        </div>
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">Y</span>
          <span>{{ props.coordinate.y?.toFixed(4) }}</span>
        </div>
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">Altitude</span>
          <span v-if="typeof props.coordinate.altitude === 'number'">{{ props.coordinate.altitude?.toFixed(2) }} meters</span>
          <span v-else class="fst-italic">Not defined</span>
        </div>
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">Pressure</span>
          <span v-if="typeof props.coordinate.pressure === 'number'">{{ props.coordinate.pressure?.toFixed(2) }} atm</span>
          <span v-else class="fst-italic">Not defined</span>
        </div>
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">Temperature</span>
          <span v-if="typeof props.coordinate.temperature === 'number'">{{ props.coordinate.temperature?.toFixed(2) }} °C</span>
          <span v-else class="fst-italic">Not defined</span>
        </div>
        <div class="list-group-item d-flex justify-content-between bg-dark border-dark">
          <span class="fw-bold">Last update</span>
          <span>{{ formatDate(props.coordinate.timestamp) }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
<script setup>
const props = defineProps({
  coordinate: {
    type: Object,
    default: () => {}
  }
})

function formatDate (_date) {
  if (_date === '') return '';
  const date = new Date(_date);

  return ("00" + date.getDate()).slice(-2)
    + "/" + ("00" + (date.getMonth() + 1)).slice(-2) 
    + "/" + date.getFullYear() + " " 
    + ("00" + date.getHours()).slice(-2) + ":" 
    + ("00" + date.getMinutes()).slice(-2) 
    + ":" + ("00" + date.getSeconds()).slice(-2);
}
</script>