import io from 'socket.io-client';

export default defineNuxtPlugin(() => {
  if (import.meta.server) return;

  const config = useRuntimeConfig();

  const socket = io(config.public.server);

  socket.syncEmit = function (...params) {
    return new Promise(function (resolve, reject) {
      try {
        socket.emit(...params, (_, results) => resolve(results));
      } catch (e) { reject(e); }
    });
  }

  return {
    provide: { socket }
  }
});
