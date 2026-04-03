/**
 * Settings store using Zustand
 */

import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';

interface SettingsState {
  // Notifications
  pushNotifications: boolean;
  criticalAlertsOnly: boolean;
  quietHoursEnabled: boolean;
  quietHoursStart: string;
  quietHoursEnd: string;

  // Data
  refreshInterval: number; // seconds
  apiEndpoint: string;

  // Display
  theme: 'light' | 'dark' | 'system';
  compactMode: boolean;

  // Actions
  setPushNotifications: (value: boolean) => void;
  setCriticalAlertsOnly: (value: boolean) => void;
  setQuietHours: (enabled: boolean, start?: string, end?: string) => void;
  setRefreshInterval: (seconds: number) => void;
  setApiEndpoint: (endpoint: string) => void;
  setTheme: (theme: 'light' | 'dark' | 'system') => void;
  setCompactMode: (value: boolean) => void;
  reset: () => void;
}

const DEFAULT_STATE = {
  pushNotifications: true,
  criticalAlertsOnly: false,
  quietHoursEnabled: false,
  quietHoursStart: '22:00',
  quietHoursEnd: '08:00',
  refreshInterval: 30,
  apiEndpoint: 'https://api.skyskynet.xdcindia.com',
  theme: 'dark' as const,
  compactMode: false,
};

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      ...DEFAULT_STATE,

      setPushNotifications: (value) => set({ pushNotifications: value }),
      setCriticalAlertsOnly: (value) => set({ criticalAlertsOnly: value }),
      setQuietHours: (enabled, start, end) =>
        set({
          quietHoursEnabled: enabled,
          ...(start && { quietHoursStart: start }),
          ...(end && { quietHoursEnd: end }),
        }),
      setRefreshInterval: (seconds) => set({ refreshInterval: seconds }),
      setApiEndpoint: (endpoint) => set({ apiEndpoint: endpoint }),
      setTheme: (theme) => set({ theme }),
      setCompactMode: (value) => set({ compactMode: value }),
      reset: () => set(DEFAULT_STATE),
    }),
    {
      name: 'settings-storage',
      storage: createJSONStorage(() => AsyncStorage),
    }
  )
);
