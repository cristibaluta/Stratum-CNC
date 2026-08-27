Listens for the UDP broadcast Makera machines send on port 3333, and lists them as they're found.

Protocol reverse-engineered from `Carvera_Controller`'s
`carveracontroller/WIFIStream.py` — the firmware broadcasts a UDP packet
roughly every second in the form:

```
MachineName,192.168.1.42,2222,0
```

(name, ip, tcp port for the command connection, busy flag)

## Troubleshooting

- **Nothing shows up**: check System Settings → Privacy & Security → Local
  Network, and make sure CarveraStudio is toggled on.
- **Still nothing**: some routers/APs isolate WiFi clients from each other
  (AP/client isolation) or don't forward broadcast packets between the
  WiFi and Ethernet segments — if your Mac is wired and the Carvera is on
  WiFi, this can block broadcasts even though both are "on the same
  network." Try connecting the Mac to the same WiFi network directly to
  rule this out.
- **Firewall prompt**: macOS may ask if MakeraStudio should accept
  incoming network connections the first time it runs — allow it.

## Next step

Once you can see your machine listed, the next piece is opening a TCP
connection to `ip:port` and sending the line-based command protocol
(`$#`, `get wcs`, `M3 S...`, etc.) that we found in `Controller.py`. That's
a good separate follow-up once discovery is confirmed working end-to-end.
