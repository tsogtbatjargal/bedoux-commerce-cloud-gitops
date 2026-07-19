import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
  },
  server: {
    // Mirrors the Kubernetes Ingress path routing (/api -> API Service) so
    // local dev, Compose, and the deployed MVP all address the API the same
    // way. Point at Compose's api service name when running under Compose.
    proxy: {
      '/api': {
        target: process.env.VITE_PROXY_TARGET ?? 'http://localhost:8000',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
    },
  },
})
