import { fetchJson } from "./provider-usage.fetch.shared.js";
import { PROVIDER_LABELS } from "./provider-usage.shared.js";
import type { ProviderUsageSnapshot } from "./provider-usage.types.js";

type DeepseekBalanceInfo = {
  currency: string;
  total_balance: string;
  granted_balance: string;
  topped_up_balance: string;
};

type DeepseekBalanceResponse = {
  is_available: boolean;
  balance_infos: DeepseekBalanceInfo[];
};

export async function fetchDeepseekUsage(
  apiKey: string,
  timeoutMs: number,
  fetchFn: typeof fetch,
): Promise<ProviderUsageSnapshot> {
  const res = await fetchJson(
    "https://api.deepseek.com/user/balance",
    {
      method: "GET",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        Accept: "application/json",
      },
    },
    timeoutMs,
    fetchFn,
  );

  if (!res.ok) {
    return {
      provider: "deepseek",
      displayName: PROVIDER_LABELS.deepseek,
      windows: [],
      error: `HTTP ${res.status}`,
    };
  }

  const data = (await res.json().catch(() => null)) as DeepseekBalanceResponse;
  if (!data || !Array.isArray(data.balance_infos)) {
    return {
      provider: "deepseek",
      displayName: PROVIDER_LABELS.deepseek,
      windows: [],
      error: "Invalid response",
    };
  }

  const balanceInfo = data.balance_infos[0];
  if (!balanceInfo) {
    return {
      provider: "deepseek",
      displayName: PROVIDER_LABELS.deepseek,
      windows: [],
      plan: "No balance info",
    };
  }

  const plan = `${balanceInfo.total_balance} ${balanceInfo.currency}`;

  return {
    provider: "deepseek",
    displayName: PROVIDER_LABELS.deepseek,
    windows: [],
    plan,
  };
}
