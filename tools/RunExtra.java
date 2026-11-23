import com.cburch.logisim.circuit.*;
import com.cburch.logisim.comp.Component;
import com.cburch.logisim.data.Value;
import com.cburch.logisim.file.Loader;
import com.cburch.logisim.gui.hex.HexFile;
import com.cburch.logisim.instance.*;
import com.cburch.logisim.proj.Project;
import com.cburch.logisim.std.memory.*;
import java.io.File;
import java.util.*;

/**
 * Ejecuta imagenes en la placa y mide los pulsos de TTY_WE y MEM_WE, y el estado tras HALT y con RESET.
 * Uso: java RunExtra.java smips.circ ciclos_max imagen.hex... (una linea EXTRA por imagen).
 */
class RunExtra {
  static CircuitState board, memoria, datapath, banco;
  static Component reset;

  static Component find(CircuitState s, String kind, String label) {
    for (var c : s.getCircuit().getNonWires())
      if (c.getFactory().getName().equals(kind) && (label == null || label.equals(c.getAttributeSet().getValue(StdAttr.LABEL))))
        return c;
    throw new AssertionError(kind + " " + label);
  }
  static CircuitState sub(CircuitState s, String kind) {
    var c = find(s, kind, null);
    return ((SubcircuitFactory) c.getFactory()).getSubstate(s, c);
  }
  static long value(String tunnel) {
    Value v = board.getValue(find(board, "Tunnel", tunnel).getLocation());
    return v.isFullyDefined() ? v.toLongValue() : -1;
  }
  static void settle() {
    board.getPropagator().propagate();
    if (board.getPropagator().isOscillating()) throw new AssertionError("Oscilacion");
  }
  static void cycle() { for (int i = 0; i < 2; i++) { board.getPropagator().toggleClocks(); settle(); } }
  static void press(boolean p) {
    board.getInstanceState(reset).setData(new InstanceDataSingleton(p ? Value.TRUE : Value.FALSE));
    board.markComponentAsDirty(reset); settle();
  }
  static MemContents ram() {
    var r = find(memoria, "RAM", null);
    return ((Mem) r.getFactory()).getContents(memoria.getInstanceState(r));
  }
  /** PC, los 32 registros y toda la RAM. */
  static String estado() {
    var pc = find(datapath, "Register", "PC");
    var s = new StringBuilder().append(datapath.getValue(pc.getEnd(0).getLocation()));
    for (var c : new TreeMap<String, Component>() {{
      for (var x : banco.getCircuit().getNonWires())
        if (x.getFactory().getName().equals("Register")) put(x.getLocation().toString(), x); }}.values())
      s.append(banco.getValue(c.getEnd(0).getLocation()));
    for (int i = 0; i < 4096; i++) s.append(ram().get(i)).append(',');
    return s.toString();
  }
  static void run(String image, int max) throws Exception {
    press(true); cycle();
    ram().clear(); HexFile.open(ram(), new File(image)); memoria.markComponentAsDirty(find(memoria, "RAM", null));
    cycle(); press(false);
    int cycles = 0, we = 0; boolean halted = false; var tty = new StringBuilder();
    while (cycles < max && !halted) {
      // valores del ciclo en curso: son los que ve el proximo flanco de subida
      if (value("MEM_WE") == 1) we++;
      if (value("TTY_WE") == 1) tty.append(String.format("%02x", value("TTY_DATA")));
      cycle(); cycles++;
      halted = value("HALT") == 1;
    }
    int cambios = 0;
    String antes = estado();
    for (int k = 0; k < 200 && halted; k++) {
      cycle();
      if (value("HALT") != 1 || value("MEM_WE") != 0 || value("TTY_WE") != 0 || !estado().equals(antes)) cambios++;
    }
    press(true); cycle();
    boolean r = value("HALT") == 0 && value("MEM_WE") == 0 && value("TTY_WE") == 0 && value("MEM_ADDR") == 0;
    press(false);
    System.out.println(String.join("\t", "EXTRA", image, "" + halted, "" + cycles, "" + we, "" + cambios, "" + r, tty));
  }
  public static void main(String[] a) {
    try {
      var file = new Loader(null).openLogisimFile(new File(a[0])); file.stopAutosaveThread(false);
      var project = new Project(file);
      project.getSimulator().setAutoPropagation(false); project.getSimulator().setAutoTicking(false);
      project.getSimulator().shutDown(); ((Thread) project.getSimulator().simThread).join(5000);
      board = CircuitState.createRootState(project, file.getCircuit("Board"), Thread.currentThread());
      project.setCircuitState(board);
      memoria = sub(board, "Memory"); reset = find(board, "Button", "Reset");
      datapath = sub(sub(board, "CPU"), "Datapath"); banco = sub(datapath, "Register_File");
      settle();
      for (int i = 2; i < a.length; i++) run(a[i], Integer.parseInt(a[1]));
      System.out.flush(); System.exit(0);
    } catch (Throwable e) { e.printStackTrace(); System.exit(1); }
  }
}
