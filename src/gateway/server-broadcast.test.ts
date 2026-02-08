import { describe, expect, it, vi } from "vitest";
import type { GatewayWsClient } from "./server/ws-types.js";
import { createGatewayBroadcaster } from "./server-broadcast.js";

type TestSocket = {
  bufferedAmount: number;
  send: (payload: string) => void;
  close: (code: number, reason: string) => void;
};

describe("gateway broadcaster", () => {
  it("filters approval and pairing events by scope", () => {
    const approvalsSocket: TestSocket = {
      bufferedAmount: 0,
      send: vi.fn(),
      close: vi.fn(),
    };
    const pairingSocket: TestSocket = {
      bufferedAmount: 0,
      send: vi.fn(),
      close: vi.fn(),
    };
    const readSocket: TestSocket = {
      bufferedAmount: 0,
      send: vi.fn(),
      close: vi.fn(),
    };

    const clients = new Set<GatewayWsClient>([
      {
        socket: approvalsSocket as unknown as GatewayWsClient["socket"],
        connect: { role: "operator", scopes: ["operator.approvals"] } as GatewayWsClient["connect"],
        connId: "c-approvals",
      },
      {
        socket: pairingSocket as unknown as GatewayWsClient["socket"],
        connect: { role: "operator", scopes: ["operator.pairing"] } as GatewayWsClient["connect"],
        connId: "c-pairing",
      },
      {
        socket: readSocket as unknown as GatewayWsClient["socket"],
        connect: { role: "operator", scopes: ["operator.read"] } as GatewayWsClient["connect"],
        connId: "c-read",
      },
    ]);

    const { broadcast, broadcastToConnIds } = createGatewayBroadcaster({ clients });

    broadcast("exec.approval.requested", { id: "1" });
    broadcast("device.pair.requested", { requestId: "r1" });

    expect(approvalsSocket.send).toHaveBeenCalledTimes(1);
    expect(pairingSocket.send).toHaveBeenCalledTimes(1);
    expect(readSocket.send).toHaveBeenCalledTimes(0);

    broadcastToConnIds("tick", { ts: 1 }, new Set(["c-read"]));
    expect(readSocket.send).toHaveBeenCalledTimes(1);
    expect(approvalsSocket.send).toHaveBeenCalledTimes(1);
    expect(pairingSocket.send).toHaveBeenCalledTimes(1);
  });

  it("assigns monotonic sequence numbers per-client even when filtered", () => {
    const s1 = { bufferedAmount: 0, send: vi.fn() };
    const s2 = { bufferedAmount: 0, send: vi.fn() };

    const clients = new Set<GatewayWsClient>([
      {
        socket: s1 as any,
        connect: { role: "operator", scopes: ["operator.approvals"] } as any,
        connId: "c1",
      },
      {
        socket: s2 as any,
        connect: { role: "operator", scopes: ["operator.pairing"] } as any,
        connId: "c2",
      },
    ]);

    const { broadcast } = createGatewayBroadcaster({ clients });

    broadcast("exec.approval.requested", { id: "1" }); // s1 gets seq 1, s2 filtered
    broadcast("device.pair.requested", { requestId: "r1" }); // s2 gets seq 1, s1 filtered
    broadcast("tick", {}); // s1 gets seq 2, s2 gets seq 2

    expect(s1.send).toHaveBeenCalledTimes(2);
    expect(JSON.parse(vi.mocked(s1.send).mock.calls[0][0]).seq).toBe(1);
    expect(JSON.parse(vi.mocked(s1.send).mock.calls[1][0]).seq).toBe(2);

    expect(s2.send).toHaveBeenCalledTimes(2);
    expect(JSON.parse(vi.mocked(s2.send).mock.calls[0][0]).seq).toBe(1);
    expect(JSON.parse(vi.mocked(s2.send).mock.calls[1][0]).seq).toBe(2);
  });
});
