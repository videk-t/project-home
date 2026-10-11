type EventName = 'onboarding_started' | 'household_created' | 'invite_sent' | 'invite_joined' | 'task_created' | 'task_completed' | 'shopping_item_added' | 'shopping_item_completed' | 'event_created' | 'expense_created' | 'bill_created' | 'settlement_created' | 'household_active_day';
type SafeProperties = Record<string, string | number | boolean | undefined>;
export const analytics = { track: (_event: EventName, _properties: SafeProperties = {}) => { /* wire a provider here; never send home text, notes, descriptions, or email. */ } };
