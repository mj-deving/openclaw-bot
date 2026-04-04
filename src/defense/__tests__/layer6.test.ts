import { describe, test, expect } from "bun:test";
import { checkPath, checkUrl, _internals } from "../layer6-access";
import type { AccessControlConfig } from "../types";

const defaultPathConfig: AccessControlConfig = {
  allowedDirectories: ["/home/openclaw/workspace", "/tmp/openclaw"],
};

describe("Layer 6: Access Control", () => {
  // ── Path Guards ────────────────────────────────────────────────────

  describe("Path guards — deny filenames", () => {
    test("denies .env files", () => {
      const result = checkPath("/home/openclaw/workspace/.env", defaultPathConfig);
      expect(result.allowed).toBe(false);
      expect(result.reason).toContain("Denied filename");
    });

    test("denies id_rsa files", () => {
      const result = checkPath("/home/openclaw/workspace/id_rsa", defaultPathConfig);
      expect(result.allowed).toBe(false);
    });

    test("denies authorized_keys", () => {
      const result = checkPath(
        "/home/openclaw/workspace/authorized_keys",
        defaultPathConfig
      );
      expect(result.allowed).toBe(false);
    });

    test("denies secrets.json", () => {
      const result = checkPath(
        "/home/openclaw/workspace/secrets.json",
        defaultPathConfig
      );
      expect(result.allowed).toBe(false);
    });

    test("denies kubeconfig", () => {
      const result = checkPath(
        "/home/openclaw/workspace/kubeconfig",
        defaultPathConfig
      );
      expect(result.allowed).toBe(false);
    });
  });

  describe("Path guards — deny extensions", () => {
    test("denies .pem files", () => {
      const result = checkPath(
        "/home/openclaw/workspace/cert.pem",
        defaultPathConfig
      );
      expect(result.allowed).toBe(false);
      expect(result.reason).toContain("Denied extension");
    });

    test("denies .p12 files", () => {
      const result = checkPath(
        "/home/openclaw/workspace/cert.p12",
        defaultPathConfig
      );
      expect(result.allowed).toBe(false);
    });

    test("denies .pfx files", () => {
      const result = checkPath(
        "/home/openclaw/workspace/cert.pfx",
        defaultPathConfig
      );
      expect(result.allowed).toBe(false);
    });

    test("denies .kdbx (KeePass) files", () => {
      const result = checkPath(
        "/home/openclaw/workspace/passwords.kdbx",
        defaultPathConfig
      );
      expect(result.allowed).toBe(false);
    });

    test("denies custom extra extensions", () => {
      const config = {
        ...defaultPathConfig,
        extraDenyExtensions: [".secret"],
      };
      const result = checkPath(
        "/home/openclaw/workspace/data.secret",
        config
      );
      expect(result.allowed).toBe(false);
    });
  });

  describe("Path guards — directory containment", () => {
    test("allows paths within allowed directories", () => {
      const result = checkPath(
        "/home/openclaw/workspace/docs/readme.md",
        defaultPathConfig
      );
      expect(result.allowed).toBe(true);
    });

    test("rejects paths outside allowed directories", () => {
      const result = checkPath("/etc/nginx/nginx.conf", defaultPathConfig);
      expect(result.allowed).toBe(false);
      expect(result.reason).toContain("outside allowed directories");
    });

    test("rejects path traversal attacks", () => {
      const result = checkPath(
        "/home/openclaw/workspace/../../../etc/passwd",
        defaultPathConfig
      );
      expect(result.allowed).toBe(false);
    });

    test("allows paths in /tmp/openclaw", () => {
      const result = checkPath(
        "/tmp/openclaw/cache/data.json",
        defaultPathConfig
      );
      expect(result.allowed).toBe(true);
    });
  });

  // ── URL Safety ─────────────────────────────────────────────────────

  describe("URL safety — scheme validation", () => {
    test("allows http URLs", async () => {
      const result = await checkUrl("http://example.com/api");
      expect(result.allowed).toBe(true);
    });

    test("allows https URLs", async () => {
      const result = await checkUrl("https://example.com/api");
      expect(result.allowed).toBe(true);
    });

    test("rejects ftp:// scheme", async () => {
      const result = await checkUrl("ftp://files.example.com/data");
      expect(result.allowed).toBe(false);
      expect(result.reason).toContain("Disallowed scheme");
    });

    test("rejects file:// scheme", async () => {
      const result = await checkUrl("file:///etc/passwd");
      expect(result.allowed).toBe(false);
    });

    test("rejects javascript: scheme", async () => {
      const result = await checkUrl("javascript:alert(1)");
      expect(result.allowed).toBe(false);
    });

    test("rejects data: scheme", async () => {
      const result = await checkUrl("data:text/html,<h1>test</h1>");
      expect(result.allowed).toBe(false);
    });
  });

  describe("URL safety — localhost/loopback", () => {
    test("rejects localhost", async () => {
      const result = await checkUrl("http://localhost:8080/admin");
      expect(result.allowed).toBe(false);
      expect(result.reason).toContain("localhost");
    });

    test("rejects 127.0.0.1", async () => {
      const result = await checkUrl("http://127.0.0.1:3000/api");
      expect(result.allowed).toBe(false);
    });

    test("rejects 0.0.0.0", async () => {
      const result = await checkUrl("http://0.0.0.0/api");
      expect(result.allowed).toBe(false);
    });

    test("rejects [::1] IPv6 loopback", async () => {
      const result = await checkUrl("http://[::1]:8080/api");
      expect(result.allowed).toBe(false);
    });
  });

  describe("URL safety — private IP detection", () => {
    test("rejects 10.x.x.x private range", async () => {
      const result = await checkUrl("http://10.0.0.1/internal");
      expect(result.allowed).toBe(false);
      expect(result.reason).toContain("private");
    });

    test("rejects 172.16.x.x private range", async () => {
      const result = await checkUrl("http://172.16.0.1/admin");
      expect(result.allowed).toBe(false);
    });

    test("rejects 192.168.x.x private range", async () => {
      const result = await checkUrl("http://192.168.1.1/config");
      expect(result.allowed).toBe(false);
    });

    test("rejects 169.254.x.x link-local range", async () => {
      const result = await checkUrl("http://169.254.169.254/metadata");
      expect(result.allowed).toBe(false);
    });
  });

  // ── isPrivateIp internal helper ────────────────────────────────────

  describe("Private IP helper", () => {
    test("identifies RFC 1918 ranges", () => {
      expect(_internals.isPrivateIp("10.0.0.1")).toBe(true);
      expect(_internals.isPrivateIp("172.16.0.1")).toBe(true);
      expect(_internals.isPrivateIp("192.168.0.1")).toBe(true);
    });

    test("identifies loopback", () => {
      expect(_internals.isPrivateIp("127.0.0.1")).toBe(true);
      expect(_internals.isPrivateIp("127.255.255.255")).toBe(true);
    });

    test("identifies RFC 6598 CGN", () => {
      expect(_internals.isPrivateIp("100.64.0.1")).toBe(true);
      expect(_internals.isPrivateIp("100.127.255.255")).toBe(true);
    });

    test("identifies RFC 5737 TEST-NET ranges", () => {
      expect(_internals.isPrivateIp("192.0.2.1")).toBe(true);
      expect(_internals.isPrivateIp("198.51.100.1")).toBe(true);
      expect(_internals.isPrivateIp("203.0.113.1")).toBe(true);
    });

    test("allows public IPs", () => {
      expect(_internals.isPrivateIp("8.8.8.8")).toBe(false);
      expect(_internals.isPrivateIp("1.1.1.1")).toBe(false);
      expect(_internals.isPrivateIp("93.184.216.34")).toBe(false);
    });

    test("identifies IPv6 loopback", () => {
      expect(_internals.isPrivateIp("::1")).toBe(true);
    });

    test("identifies IPv6 unique local", () => {
      expect(_internals.isPrivateIp("fc00::1")).toBe(true);
      expect(_internals.isPrivateIp("fd12:3456:789a::1")).toBe(true);
    });

    test("identifies RFC 3849 documentation prefix (M-3)", () => {
      expect(_internals.isPrivateIp("2001:db8::1")).toBe(true);
      expect(_internals.isPrivateIp("2001:0db8:85a3::8a2e:370:7334")).toBe(true);
    });

    test("identifies IPv6 multicast (M-3)", () => {
      expect(_internals.isPrivateIp("ff02::1")).toBe(true);
      expect(_internals.isPrivateIp("ff01::1")).toBe(true);
    });

    test("does not false-positive on public IPv6 (M-3)", () => {
      expect(_internals.isPrivateIp("2607:f8b0:4004:800::200e")).toBe(false);
    });
  });

  // ── DNS Timeout (M-5) ───────────────────────────────────────────

  describe("DNS timeout", () => {
    test("DNS_TIMEOUT_MS is set to 3 seconds", () => {
      expect(_internals.DNS_TIMEOUT_MS).toBe(3_000);
    });
  });

  // ── Resolved IPs (C-2) ─────────────────────────────────────────

  describe("DNS pinning — resolvedIps", () => {
    test("returns resolvedIps array for allowed URLs", async () => {
      const result = await checkUrl("https://example.com");
      // Whether DNS resolves or not, the field should exist
      expect(result).toHaveProperty("resolvedIps");
      if (result.allowed) {
        expect(Array.isArray(result.resolvedIps)).toBe(true);
      }
    });
  });
});
