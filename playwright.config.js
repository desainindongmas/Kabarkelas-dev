import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir:'tests/browser', fullyParallel:true,
  use:{baseURL:'http://127.0.0.1:4173',headless:true},
  webServer:{command:'npm run dev -- --host 127.0.0.1 --port 4173',url:'http://127.0.0.1:4173',reuseExistingServer:false,
    env:{VITE_SUPABASE_URL:'https://g05-ui-test.supabase.co',VITE_SUPABASE_PUBLISHABLE_KEY:'sb_publishable_ui_test_only'}},
});
