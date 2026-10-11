import { Tabs } from 'expo-router';
import { ColorValue, Text } from 'react-native';
import { useAppTheme } from '../../design-system/theme';

const icon = (label: string) => function TabIcon({ color }: { color: ColorValue }) { return <Text style={{ color, fontSize: 18 }}>{label}</Text>; };
export default function TabLayout() {
  const { colors } = useAppTheme();
  return <Tabs screenOptions={{ headerShown: false, tabBarActiveTintColor: colors.accent, tabBarInactiveTintColor: colors.textSecondary, tabBarStyle: { backgroundColor: colors.surface, borderTopColor: colors.border } }}>
    <Tabs.Screen name="index" options={{ title: 'Today', tabBarIcon: icon('●') }} />
    <Tabs.Screen name="tasks" options={{ title: 'Tasks', tabBarIcon: icon('✓') }} />
    <Tabs.Screen name="create" options={{ title: '+', tabBarIcon: icon('+') }} />
    <Tabs.Screen name="calendar" options={{ title: 'Calendar', tabBarIcon: icon('□') }} />
    <Tabs.Screen name="home" options={{ title: 'Home', tabBarIcon: icon('⌂') }} />
  </Tabs>;
}
