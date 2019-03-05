defmodule VICI.Server do
  use GenServer
  require Logger

  import VICI.Protocol

  def start_link(port) do
    GenServer.start_link(__MODULE__, port)
  end

  def init(port) do
    {:ok, l_sock} = :gen_tcp.listen(port, [:binary, {:mode, :binary}, {:packet, 4}])
    Process.send_after(self(), :accept, 0)
    {:ok, {l_sock, false}}
  end

  defp reply(data, sock) do
    Logger.info "Replying: #{inspect data}"
    Logger.info "Sending to: #{inspect sock}"
    packet = <<1::integer-size(8)>> <> serialize(data)
    :gen_tcp.send(sock, packet)
  end

  defp confirm(data, sock) do
    Logger.info "Confirming"
    Logger.info "Sending to: #{inspect sock}"
    packet = <<5::integer-size(8)>> <> serialize(data)
    :gen_tcp.send(sock, packet)
  end

  defp stream(data, sock) do
    Logger.info "Stream: #{inspect data}"
    packet = <<7::integer-size(8)>> <> serialize(data)
    :gen_tcp.send(sock, packet)
  end

  defp unknown_command(sock) do
    Logger.info "Uknown Command"
    packet = <<2::integer-size(8)>>
    :gen_tcp.send(sock, packet)
  end

  defp unknown_event(sock) do
    Logger.info "Uknown Event"
    packet = <<6::integer-size(8)>>
    :gen_tcp.send(sock, packet)
  end

  def handle_info(:accept, {l_sock, _client}) do
    {:ok, s} = :gen_tcp.accept(l_sock)
    Logger.info "Accepted #{inspect s}"
    {:noreply, {l_sock, true}}
  end

  def handle_info({:tcp, sock, <<0::integer, cmd_len::integer, cmd::binary-size(cmd_len), args::binary()>>}, l_sock) do
    Logger.info("Command: #{cmd}")
    Logger.info("Client Socket: #{inspect sock}")
    case handle_command(cmd, sock, deserialize(args)) do
      :unknown_cmd -> unknown_command(sock)
      res -> reply(res, sock)
    end
    {:noreply, l_sock}
  end

  def handle_info({:tcp, sock, <<3::integer, cmd_len::integer, cmd::binary-size(cmd_len), args::binary()>>}, l_sock) do
    Logger.info("Command: #{cmd}")
    Logger.info("Client Socket: #{inspect sock}")
    case handle_event(cmd, sock, deserialize(args)) do
      :unknown_cmd -> unknown_event(sock)
      res -> confirm(res, sock)
    end
    {:noreply, l_sock}
  end

  def handle_info({:tcp, sock, <<4::integer, cmd_len::integer, cmd::binary-size(cmd_len)>>}, {l_sock, _c}) do
    Logger.info("Unregister: #{cmd}")
    :gen_tcp.close(sock)
    {:noreply, {l_sock, false}}
  end

  def handle_info({:tcp, s, data}, l_sock) do
    Logger.info "Got data: #{inspect data}"
    unknown_command(s)
    {:noreply, l_sock}
  end

  def handle_info({:tcp_closed, s}, {l_sock, _client}) do
    Logger.info "Socket Closed: #{inspect s}"
    Process.send_after(self(), :accept, 0)
    {:noreply, {l_sock, false}}
  end

  def handle_info({:sas, sock}, {_l_sock, true} = state) do
    Enum.each(1..100, fn _i ->
      stream(generate_sas(), sock)
      Process.sleep(100)
    end)
    {:noreply, state}
  end

  def handle_info({:sas, _sock}, state), do: {:noreply, state}

  def handle_info({:log, sock}, {_l_sock, true} = state) do
    Enum.each(1..100, fn _i ->
      stream(generate_log(), sock)
      Process.sleep(100)
    end)
    {:noreply, state}
  end

  def handle_info({:log, _sock}, state), do: {:noreply, state}

  defp handle_event(event, sock, args \\ %{})
  defp handle_event("log", sock, _args) do
    Process.send_after(self(), {:log, sock}, 100)
    %{}
  end

  defp handle_event(_, _, _), do: :unknown_cmd

  defp handle_command(cmd, sock, args \\ %{})
  defp handle_command("version", _sock, _args) do
    %{
      daemon: "charon",
      machine: "x86_64",
      release: "4.15.0-45-generic",
      sysname: "Linux",
      version: "5.4.0"
    }
  end

  defp handle_command("stats", _sock, _args) do
    %{
      ikesas: %{"half-open": 0, total: 0},
      plugins: ["charon", "random", "nonce", "x509", "revocation", "constraints",
        "pubkey", "pkcs1", "pkcs7", "pkcs8", "pkcs12", "pgp", "dnskey", "sshkey",
        "pem", "openssl", "fips-prf", "gmp", "xcbc", "cmac", "curl", "sqlite",
        "attr", "kernel-netlink", "resolve", "socket-default", "farp", "stroke",
        "vici", "updown", "eap-identity", "eap-sim", "eap-aka", "eap-aka-3gpp2",
        "eap-simaka-pseudonym", "eap-simaka-reauth", "eap-md5", "eap-mschapv2",
        "eap-radius", "eap-tls", "xauth-generic", "xauth-eap", "dhcp", "unity"
      ],
      queues: %{critical: 0, high: 0, low: 0, medium: 0}, scheduled: 0,
      uptime: %{running: "2 hours", since: "Mar 03 19:14:47 2019"},
      workers: %{active: %{critical: 4, high: 0, low: 0, medium: 1}, idle: 11,
      total: 16}
    }
  end

  defp handle_command("list-sas", sock, _args) do
    Process.send_after(self(), {:sas, sock}, 100)
    %{}
  end

  defp handle_command(_, _, _), do: :unknown_cmd

  defp generate_log do
    %{
      group: "ike",
      level: 2,
      thread: 4,
      "ikesa-name": "kiosk-10-a",
      "ikesa-uniqued": "sd876876",
      msg: "this is a log message"
    }
  end

  defp generate_sas do
    %{
      id: :rand.uniform(99999),
      bytes_in: :rand.uniform(9999999999999),
      bytes_out: :rand.uniform(9999999999999),
      packets_in: :rand.uniform(9999999999999),
      packets_out: :rand.uniform(9999999999999)
    }
  end
end
