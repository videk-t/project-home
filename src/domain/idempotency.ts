export function clientMutationId() { return crypto.randomUUID(); }
export function isSameMutation(existing: readonly string[], candidate: string) { return existing.includes(candidate); }
