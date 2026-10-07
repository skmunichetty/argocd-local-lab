import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    // For `npm run dev` only: forward /api to a locally running API (`dotnet run` in src/api).
    proxy: { '/api': 'http://localhost:5000' },
  },
});
