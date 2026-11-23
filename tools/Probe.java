import com.cburch.logisim.circuit.CircuitState;
import com.cburch.logisim.comp.Component;
import com.cburch.logisim.data.*;
import com.cburch.logisim.file.Loader;
import com.cburch.logisim.instance.*;
import com.cburch.logisim.proj.Project;
import com.cburch.logisim.std.wiring.Pin;
import java.io.*;
import java.util.*;

/**
 * Simula un subcircuito aislado. Uso: java Probe.java archivo.circ Circuito < ordenes
 * Ordenes: "set PIN hex" fuerza una entrada; "clk" da un ciclo en el pin CLK; "show" imprime las salidas.
 */
class Probe {
  static CircuitState st;
  static final Map<String, Component> pins = new LinkedHashMap<>();

  static void set(String pin, long v) {
    var c = pins.get(pin);
    if (c == null) throw new IllegalArgumentException("No existe el pin " + pin);
    var w = c.getAttributeSet().getValue(StdAttr.WIDTH);
    Pin.FACTORY.driveInputPin(st.getInstanceState(c), Value.createKnown(w, v));
    st.getInstanceState(c).fireInvalidated();
    st.markComponentAsDirty(c);
  }
  static void settle() {
    st.getPropagator().propagate();
    if (st.getPropagator().isOscillating()) throw new AssertionError("Oscilacion");
  }
  static void show() {
    settle();
    var out = new StringJoiner(" ");
    for (var e : pins.entrySet()) {
      if (Pin.FACTORY.isInputPin(Instance.getInstanceFor(e.getValue()))) continue;
      Value v = st.getValue(e.getValue().getLocation());
      out.add(e.getKey() + "=" + (v.isFullyDefined() ? Long.toHexString(v.toLongValue()) : "indefinido"));
    }
    System.out.println(out);
  }
  public static void main(String[] a) {
    try {
      var file = new Loader(null).openLogisimFile(new File(a[0]));
      file.stopAutosaveThread(false);
      var project = new Project(file);
      project.getSimulator().setAutoPropagation(false);
      project.getSimulator().setAutoTicking(false);
      project.getSimulator().shutDown();
      ((Thread) project.getSimulator().simThread).join(5000);
      st = CircuitState.createRootState(project, file.getCircuit(a[1]), Thread.currentThread());
      for (var c : st.getCircuit().getNonWires())
        if (c.getFactory() instanceof Pin) pins.put(c.getAttributeSet().getValue(StdAttr.LABEL), c);
      var in = new BufferedReader(new InputStreamReader(System.in));
      for (String l; (l = in.readLine()) != null; ) {
        var t = l.trim().split("\\s+");
        switch (t[0]) {
          case "set" -> set(t[1], Long.parseLong(t[2], 16));
          case "clk" -> { settle(); set("CLK", 1); settle(); set("CLK", 0); settle(); }
          case "show" -> show();
          default -> { if (!t[0].isEmpty()) throw new IllegalArgumentException("Orden desconocida: " + l); }
        }
      }
      System.out.flush();
      System.exit(0);
    } catch (Throwable e) { e.printStackTrace(); System.exit(1); }
  }
}
