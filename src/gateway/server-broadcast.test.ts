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
        eventSeq: 0,
      },
      {
        socket: pairingSocket as unknown as GatewayWsClient["socket"],
        connect: { role: "operator", scopes: ["operator.pairing"] } as GatewayWsClient["connect"],
        connId: "c-pairing",
        eventSeq: 0,
      },
      {
        socket: readSocket as unknown as GatewayWsClient["socket"],
        connect: { role: "operator", scopes: ["operator.read"] } as GatewayWsClient["connect"],
        connId: "c-read",
        eventSeq: 0,
      },
    ]);

    const { broadcast, broadcastToConnIds } = createGatewayBroadcaster({ clients });

    broadcast("exec.approval.requested", { id: "1" });
    broadcast("device.pair.requested", { requestId: "r1" });

    expect(approvalsSocket.send).toHaveBeenCalledTimes(1);
    expect(pairingSocket.send).toHaveBeenCalledTimes(1);
    expect(readSocket.send).toHaveBeenCalledTimes(0);

    // Verify sequences are per-client
    const approvalsFirstCall = JSON.parse(vi.mocked(approvalsSocket.send).mock.calls[0][0]);
    const pairingFirstCall = JSON.parse(vi.mocked(pairingSocket.send).mock.calls[0][0]);
    expect(approvalsFirstCall.seq).toBe(1);
    expect(pairingFirstCall.seq).toBe(1);

    broadcastToConnIds("tick", { ts: 1 }, new Set(["c-read"]));
    expect(readSocket.send).toHaveBeenCalledTimes(1);
    expect(approvalsSocket.send).toHaveBeenCalledTimes(1);
    expect(pairingSocket.send).toHaveBeenCalledTimes(1);
  });

  it("does not create gaps when events are scope-filtered", () => {
    const c1Socket = { bufferedAmount: 0, send: vi.fn(), close: vi.fn() };
    const c2Socket = { bufferedAmount: 0, send: vi.fn(), close: vi.fn() };

    const c1: GatewayWsClient = {
      socket: c1Socket as any,
      connect: { role: "operator", scopes: ["operator.admin"] } as any,
      connId: "c1",
      eventSeq: 0,
    };
    const c2: GatewayWsClient = {
      socket: c2Socket as any,
      connect: { role: "operator", scopes: ["operator.read"] } as any,
      connId: "c2",
      eventSeq: 0,
    };

    const { broadcast } = createGatewayBroadcaster({ clients: new Set([c1, c2]) });

    // Event 1: All receive
    broadcast("tick", { n: 1 });
    // Event 2: Only C1 (admin) receives
    broadcast("exec.approval.requested", { id: "req-1" });
    // Event 3: All receive
    broadcast("tick", { n: 2 });

    expect(c1Socket.send).toHaveBeenCalledTimes(3);
    expect(c2Socket.send).toHaveBeenCalledTimes(2);

    const c1Frames = c1Socket.send.mock.calls.map((c) => JSON.parse(c[0]));
    const c2Frames = c2Socket.send.mock.calls.map((c) => JSON.parse(c[0]));

    // C1 sees 1, 2, 3
    expect(c1Frames[0].seq).toBe(1);
    expect(c1Frames[1].seq).toBe(2);
    expect(c1Frames[2].seq).toBe(3);

    // C2 sees 1, 2 (no gap, because sequence is per-client)
    expect(c2Frames[0].seq).toBe(1);
    expect(c2Frames[1].seq).toBe(2); // This was broadcast 3 globally, but it's c2's second broadcast.
  });
});
