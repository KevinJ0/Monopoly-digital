class BleProtocol {
  BleProtocol._();

  // Versión 2: UUID nuevo para invalidar tablas GATT antiguas almacenadas por
  // Android durante el desarrollo de la primera versión del servidor.
  static const serviceUuid = '22345678-0000-1000-8000-00805f9b34fb';
  static const characteristicUuid = '22345678-0001-1000-8000-00805f9b34fb';
}
