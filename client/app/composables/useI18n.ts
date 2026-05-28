import { ref } from 'vue'

const translations = {
  en: {
    brand: "Car Tracking",
    admin: "Admin",
    logout: "Logout",
    language: "Language",
    theme: "Theme",
    dashboardTitle: "Devices Dashboard",
    dashboardSubtitle: "Real-time GPS telemetry and historical analysis platform",
    devices: "Devices",
    name: "Name",
    edit: "Edit",
    realtime: "Realtime",
    history: "History",
    noDevices: "No devices found. Start transmitting to see them!",
    editDeviceTitle: "Edit Device Name",
    saveChanges: "Save Changes",
    close: "Close",
    realtimeTitle: "Realtime Tracking",
    noCoordinates: "Cannot load the map without any coordinates",
    goToHistory: "Go to history",
    historyTitle: "Telemetry History",
    play: "Play",
    pause: "Pause",
    stop: "Stop",
    stepTimeout: "Step timeout",
    filters: "Search Filters",
    search: "Search",
    goToRealtime: "Go to realtime",
    graphs: "Telemetry Graphs",
    graphsSubtitle: "Historical altitude, atmospheric pressure, and core temperatures",
    altitude: "Altitude",
    pressure: "Pressure",
    temperature: "Temperature",
    deviceCardTitle: "Device Details",
    allDevices: "All Devices",
    devId: "ID",
    devName: "Name",
    devImei: "IMEI",
    devManufacturer: "Manufacturer",
    devModel: "Model",
    devRevision: "Revision",
    notDefined: "Not defined",
    positionCardTitle: "Position Details",
    posLat: "Latitude (X)",
    posLng: "Longitude (Y)",
    posAltitude: "Altitude",
    posPressure: "Pressure",
    posTemperature: "Temperature",
    posLastUpdate: "Last Update",
    posGoogle: "Google Maps",
    active: "Active",
    na: "N/A",
    msUnit: "ms",
    time: "Time"
  },
  it: {
    brand: "Car Tracking",
    admin: "Admin",
    logout: "Esci",
    language: "Lingua",
    theme: "Tema",
    dashboardTitle: "Pannello Dispositivi",
    dashboardSubtitle: "Piattaforma di telemetria GPS in tempo reale e analisi storica",
    devices: "Dispositivi",
    name: "Nome",
    edit: "Modifica",
    realtime: "Tempo Reale",
    history: "Storico",
    noDevices: "Nessun dispositivo trovato. Avvia la trasmissione per vederli!",
    editDeviceTitle: "Modifica Nome Dispositivo",
    saveChanges: "Salva Modifiche",
    close: "Chiudi",
    realtimeTitle: "Tracciamento in Tempo Reale",
    noCoordinates: "Impossibile caricare la mappa senza coordinate",
    goToHistory: "Vai allo storico",
    historyTitle: "Storico Telemetria",
    play: "Avvia",
    pause: "Pausa",
    stop: "Ferma",
    stepTimeout: "Intervallo passi",
    filters: "Filtri di Ricerca",
    search: "Cerca",
    goToRealtime: "Vai al tempo reale",
    graphs: "Grafici di Telemetria",
    graphsSubtitle: "Andamento storico di altitudine, pressione atmosferica e temperature interne",
    altitude: "Altitudine",
    pressure: "Pressione",
    temperature: "Temperatura",
    deviceCardTitle: "Dettagli Dispositivo",
    allDevices: "Tutti i Dispositivi",
    devId: "ID",
    devName: "Nome",
    devImei: "IMEI",
    devManufacturer: "Produttore",
    devModel: "Modello",
    devRevision: "Revisione",
    notDefined: "Non definito",
    positionCardTitle: "Dati Posizione",
    posLat: "Latitudine (X)",
    posLng: "Longitudine (Y)",
    posAltitude: "Altitudine",
    posPressure: "Pressione",
    posTemperature: "Temperatura",
    posLastUpdate: "Ultimo Aggiornamento",
    posGoogle: "Google Maps",
    active: "Attivo",
    na: "N/D",
    msUnit: "ms",
    time: "Tempo"
  }
}

const currentLocale = ref<'en' | 'it'>('en')

export function useI18n() {
  if (import.meta.client) {
    const saved = localStorage.getItem('user-locale')
    if (saved === 'it' || saved === 'en') {
      currentLocale.value = saved
    }
  }

  const setLocale = (locale: 'en' | 'it') => {
    currentLocale.value = locale
    if (import.meta.client) {
      localStorage.setItem('user-locale', locale)
    }
  }

  const t = (key: keyof typeof translations['en']): string => {
    const localeDict = translations[currentLocale.value] || translations.en
    return localeDict[key] || translations.en[key] || String(key)
  }

  return {
    locale: currentLocale,
    setLocale,
    t
  }
}
