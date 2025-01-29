import axios from 'axios'

export const useApi = () => {
  const config = useRuntimeConfig();
  const baseURL = config.public.server;

  return axios.create({ baseURL });
}
