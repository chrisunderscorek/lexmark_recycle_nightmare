  lexmark_toner_info.sh is a small Bash helper for Lexmark network printers. It discovers a Lexmark
  printer via CUPS/IPP, reads printer, toner, and imaging kit data from the embedded web interface, and
  writes the result as both text and JSON.

  The script is mainly useful when Lexmark’s recycling return form asks for hard-to-find values such as
  the printer serial number and toner serial number. It also derives the digit-only recycling value from
  toner serial numbers like CAP... or SCAP....

  Tested with a Lexmark MB2442adwe without web interface authentication enabled.
