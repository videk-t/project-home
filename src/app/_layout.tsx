import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { AppThemeProvider, useAppTheme } from '../design-system/theme';

function Navigator() {
  const { mode } = useAppTheme();
  return <><StatusBar style={mode === 'dark' ? 'light' : 'dark'} /><Stack screenOptions={{ headerShown: false }} /></>;
}

export default function RootLayout() {
  const [client] = useState(() => new QueryClient({ defaultOptions: { queries: { staleTime: 30_000, retry: 2 } } }));
  return <SafeAreaProvider><QueryClientProvider client={client}><AppThemeProvider><Navigator /></AppThemeProvider></QueryClientProvider></SafeAreaProvider>;
}
