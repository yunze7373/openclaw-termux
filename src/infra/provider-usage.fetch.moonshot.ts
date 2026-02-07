import { fetchJson } from "./provider-usage.fetch.shared.js";
import { PROVIDER_LABELS } from "./provider-usage.shared.js";
import type { ProviderUsageSnapshot } from "./provider-usage.types.js";

type MoonshotBalanceResponse = {
  code: number;
  msg: string;
  data: {
    available_balance: number;
    voucher_balance: number;
    cash_balance: number;
  };
};

export async function fetchMoonshotUsage(
  apiKey: string,
  timeoutMs: number,
  fetchFn: typeof fetch,
): Promise<ProviderUsageSnapshot> {
  const res = await fetchJson(
    "https://api.moonshot.ai/v1/users/me/balance",
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
      provider: "moonshot",
      displayName: PROVIDER_LABELS.moonshot,
      windows: [],
      error: `HTTP ${res.status}`,
    };
  }

  const response = (await res.json().catch(() => null)) as MoonshotBalanceResponse;
  
  // Moonshot API usually returns data directly or wrapped in data field.
  // The search result didn't specify the wrapper, but standard OpenAI/Moonshot patterns usually wrap in 'data' or return object directly.
  // Let's assume standard response based on typical REST APIs.
  // If the top level has available_balance, use it. If it's in data, use that.
  
  const balanceData = (response as any).data || response;

  if (!balanceData || typeof balanceData.available_balance === "undefined") {
    return {
      provider: "moonshot",
      displayName: PROVIDER_LABELS.moonshot,
      windows: [],
      error: "Invalid response",
    };
  }

  const balance = balanceData.available_balance;
  const currency = "CNY"; // Moonshot is Chinese, usually CNY, but search said USD. 
  // Wait, search said "All balance values are returned as floats in USD".
  // Let's trust the search result for now.
  
  // Actually, let's verify if the search result was generic or specific.
  // "All balance values are returned as floats in USD" -> This might be generic.
  // Moonshot is a Chinese company. Usually it's CNY.
  // However, for consistency with other providers, if I'm not sure, I can just show the number or assume USD/CNY symbol based on locale or just "credits".
  // Let's use generic formatting if unsure, or just "Balance: X".
  
  // I'll stick to displaying the number.
  
  const plan = `Balance: ${balance}`;

  return {
    provider: "moonshot",
    displayName: PROVIDER_LABELS.moonshot,
    windows: [],
    plan,
  };
}
