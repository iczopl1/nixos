import gi, sys
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
Atspi.init()
desk = Atspi.get_desktop(0)
for i in range(desk.get_child_count()):
    app = desk.get_child_at_index(i)
    print("APP", app.get_name(), "toolkit", app.get_toolkit_name() if hasattr(app,"get_toolkit_name") else "?")
    for j in range(min(app.get_child_count(), 6)):
        w = app.get_child_at_index(j)
        if not w: continue
        try:
            e = w.get_extents(Atspi.CoordType.SCREEN)
            print("   win", repr(w.get_name()), w.get_role_name(), e.x, e.y, e.width, e.height,
                  "states:", "ACTIVE" if w.get_state_set().contains(Atspi.StateType.ACTIVE) else "")
        except Exception as ex:
            print("   win err", ex)
