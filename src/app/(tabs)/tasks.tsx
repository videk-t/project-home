import { ScrollView, Text, View } from 'react-native';
import { Heading, Screen, Body, Card } from '../../design-system/primitives';
import { TaskRow } from '../../components/TaskRow';
import { useTaskStore } from '../../features/tasks/task-store';
import { useAppTheme } from '../../design-system/theme';
export default function TasksScreen() { const { tasks, toggle } = useTaskStore(); const { colors } = useAppTheme(); return <Screen><ScrollView contentContainerStyle={{ gap: 14 }}><View><Heading>Tasks</Heading><Body muted>Shared work, without the management.</Body></View><Card>{tasks.map((task) => <TaskRow key={task.id} task={task} onToggle={() => toggle(task.id)} />)}</Card><Text style={{ color: colors.textSecondary, fontSize: 13 }}>Swipe actions and details are connected when a Supabase household is configured.</Text></ScrollView></Screen>; }
