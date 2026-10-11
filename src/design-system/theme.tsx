import { createContext, ReactNode, useContext, useMemo, useState } from 'react';
import { Appearance } from 'react-native';

export const light = { background: '#F7F7F8', surface: '#FFFFFF', surfaceSecondary: '#F0F0F2', text: '#111113', textSecondary: '#6B6B73', border: '#E3E3E7', accent: '#6257D9', danger: '#C93C4A', success: '#237A57' } as const;
export const dark = { background: '#0D0D0F', surface: '#161619', surfaceSecondary: '#1D1D21', text: '#F5F5F7', textSecondary: '#98989F', border: '#29292E', accent: '#9B91FF', danger: '#FF6B7A', success: '#5BC793' } as const;
type Mode = 'system' | 'light' | 'dark'; type Theme = Record<keyof typeof light, string>;
const ThemeContext = createContext<{ colors: Theme; mode: Exclude<Mode, 'system'>; preference: Mode; setPreference: (mode: Mode) => void } | null>(null);
export function AppThemeProvider({ children }: { children: ReactNode }) { const [preference, setPreference] = useState<Mode>('system'); const system = Appearance.getColorScheme(); const mode: Exclude<Mode, 'system'> = preference === 'system' ? (system === 'dark' ? 'dark' : 'light') : preference; const value = useMemo(() => ({ colors: mode === 'dark' ? dark : light, mode, preference, setPreference }), [mode, preference]); return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>; }
export function useAppTheme() { const value = useContext(ThemeContext); if (!value) throw new Error('AppThemeProvider is required'); return value; }
