# Zasilanie: laptop sam się NIE usypia - ma móc liczyć/kompilować
# z zamkniętą klapą, na zasilaczu i na baterii.
# Uśpienie TYLKO ręcznie: krótkie naciśnięcie przycisku zasilania (albo `systemctl suspend`).
{ ... }:

{
  services.logind.settings.Login = {
    # Przycisk zasilania: krótko = uśpij, długo = wyłącz.
    HandlePowerKey = "suspend";
    HandlePowerKeyLongPress = "poweroff";

    # Zamknięcie klapy, bezczynność, klawisze uśpienia/hibernacji: nic.
    HandleLidSwitch = "ignore";              # na baterii
    HandleLidSwitchExternalPower = "ignore"; # na zasilaczu
    HandleLidSwitchDocked = "ignore";        # z monitorem zewnętrznym
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    IdleAction = "ignore";
  };

  # Żeby zamknięcie klapy usypiało: HandleLidSwitch = "suspend".
}
