<template>
  <div class="min-h-screen flex flex-col transition-colors duration-300" style="background: var(--bg-gradient)">
    <Navbar />
    
    <div class="flex-grow container mx-auto px-4 py-12">
      <!-- Title Block -->
      <div class="text-center mb-12">
        <h1 class="text-4xl md:text-5xl font-extrabold tracking-tight mb-3 tracking-title text-title">
          🚗 {{ t('dashboardTitle') }}
        </h1>
        <p class="text-text-muted max-w-xl mx-auto text-base sm:text-lg transition-colors duration-300">
          {{ t('dashboardSubtitle') }}
        </p>
      </div>

      <!-- Main devices list -->
      <div class="flex justify-center w-full">
        <div v-if="results?.total > 0" class="w-full max-w-5xl">
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <div v-for="row in results.rows" :key="row.id" class="col">
              <div class="glass-panel p-6 h-full flex flex-col justify-between hover:-translate-y-1.5 hover:shadow-indigo-500/10 hover:border-indigo-500/40 transition duration-300">
                <div>
                  <!-- Device Avatar & Header -->
                  <div class="flex items-center justify-between mb-4">
                    <div class="flex items-center gap-3">
                      <div class="w-12 h-12 rounded-xl bg-indigo-500/10 border border-indigo-500/25 flex items-center justify-center">
                        <span class="text-2xl">🏎️</span>
                      </div>
                      <div>
                        <h5 class="text-base font-bold text-title truncate max-w-[130px]">{{ row.name }}</h5>
                        <small class="text-text-muted text-xs font-mono">IMEI: {{ row.imei }}</small>
                      </div>
                    </div>
                    <span class="px-2.5 py-1 rounded-full text-xs font-semibold bg-badge-bg text-badge-text border border-card-border/50">
                      {{ t('active') }}
                    </span>
                  </div>

                  <!-- Device specs detail -->
                  <div class="border-t border-card-border/30 pt-3 mb-5">
                    <div class="flex justify-between text-xs text-text-muted mb-2">
                      <span>{{ t('devManufacturer') }}</span>
                      <span class="font-medium text-title">{{ row.manufacturer || t('na') }}</span>
                    </div>
                    <div class="flex justify-between text-xs text-text-muted">
                      <span>{{ t('devModel') }}</span>
                      <span class="font-medium text-title">{{ row.model || t('na') }}</span>
                    </div>
                  </div>
                </div>

                <!-- Actions -->
                <div class="flex gap-2 mt-2">
                  <button class="flex-1 px-3 py-2 rounded-lg text-xs font-semibold bg-btn-sec-bg border border-btn-sec-border hover:bg-btn-sec-hover text-btn-sec-text transition duration-200 cursor-pointer" @click="openModal(row)">
                    {{ t('edit') }}
                  </button>
                  <nuxt-link :to="`/device/${row.id}/realtime`" class="flex-1">
                    <button class="w-full px-3 py-2 rounded-lg text-xs font-semibold bg-gradient-to-br from-indigo-500 to-indigo-600 hover:from-indigo-600 hover:to-indigo-700 text-white shadow-md hover:shadow-lg transition duration-200 cursor-pointer text-center">
                      {{ t('realtime') }}
                    </button>
                  </nuxt-link>
                  <nuxt-link :to="`/device/${row.id}/history`" class="flex-1">
                    <button class="w-full px-3 py-2 rounded-lg text-xs font-semibold bg-btn-sec-bg border border-btn-sec-border hover:bg-btn-sec-hover text-btn-sec-text transition duration-200 cursor-pointer text-center">
                      {{ t('history') }}
                    </button>
                  </nuxt-link>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div v-else class="text-center py-12">
          <div class="glass-panel inline-block p-8 text-center max-w-md">
            <span class="text-5xl mb-4 block">📡</span>
            <h4 class="text-lg font-bold text-title mb-2">{{ t('noDevices') }}</h4>
          </div>
        </div>
      </div>

      <!-- Edit Modal (Custom Tailwind Vue modal!) -->
      <div v-if="isModalOpen" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm transition-opacity duration-300">
        <div class="glass-panel w-full max-w-md p-6 relative flex flex-col shadow-2xl">
          <div class="flex justify-between items-center mb-4 pb-1">
            <h5 class="text-lg font-bold text-title m-0">{{ t('editDeviceTitle') }}</h5>
            <button type="button" class="w-8 h-8 rounded-full flex items-center justify-center hover:bg-btn-sec-hover text-title cursor-pointer font-bold transition duration-200" @click="closeModal">✕</button>
          </div>
          
          <div class="py-4">
            <!-- Custom Styled Floating Input -->
            <div class="relative">
              <input id="deviceNameInput" v-model="editDevice.name" type="text" class="w-full px-4 py-3.5 rounded-lg border border-input-border bg-input-bg text-body-text placeholder-transparent focus:outline-none focus:border-input-focus-border focus:ring-4 focus:ring-glow/20 transition duration-200 text-sm peer" placeholder="Device Name" @keyup.enter="saveDevice">
              <label for="deviceNameInput" class="absolute left-4 top-1 text-xs text-text-muted transition-all duration-200 peer-placeholder-shown:text-sm peer-placeholder-shown:top-3.5 peer-focus:top-1 peer-focus:text-xs peer-focus:text-indigo-400 select-none pointer-events-none">
                {{ t('name') }}
              </label>
            </div>
          </div>
          
          <div class="flex justify-end gap-3 mt-4 pt-1">
            <button type="button" class="px-4 py-2 rounded-lg text-sm font-semibold bg-btn-sec-bg border border-btn-sec-border hover:bg-btn-sec-hover text-btn-sec-text transition duration-200 cursor-pointer" @click="closeModal">
              {{ t('close') }}
            </button>
            <button type="button" class="px-4 py-2 rounded-lg text-sm font-semibold bg-gradient-to-br from-indigo-500 to-indigo-600 hover:from-indigo-600 hover:to-indigo-700 text-white shadow-md hover:shadow-lg transition duration-200 cursor-pointer" @click="saveDevice">
              {{ t('saveChanges') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { useI18n } from '~/composables/useI18n'
import { ref, onMounted, onBeforeUnmount } from 'vue'

const { t } = useI18n()

useHead({ title: 'Car tracking - Devices' });

const config = useRuntimeConfig();
const results = ref({});

const { data } = await useAsyncData('devices', () => $fetch(config.public.server + '/api/devices', { query: { pageSize: 100 } }));

results.value = data.value;
const { $socket } = useNuxtApp();

const editDevice = ref({});
const isModalOpen = ref(false);

function openModal (device) {
  editDevice.value = JSON.parse(JSON.stringify(device));
  isModalOpen.value = true;
}

function closeModal () {
  isModalOpen.value = false;
}

function saveDevice () {
  $fetch(config.public.server + '/api/devices/' + editDevice.value.id, {
    method: 'PUT',
    body: { name: editDevice.value.name }
  });
  closeModal();
}

onMounted(() => { $socket.on('devices.changed', refreshList); });
onBeforeUnmount(() => { $socket.off('devices.changed'); })

async function refreshList () {
  results.value = await $socket.syncEmit('call', 'devices.list', { pageSize: 100 });
}
</script>

<style scoped>
.tracking-title {
  background: linear-gradient(135deg, var(--title-color) 30%, #a5b4fc 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}
</style>
