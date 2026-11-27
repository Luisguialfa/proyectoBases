/*
==========================================================================================
 02_datos.sql  —  Datos de prueba de tiendaDeportiva

------------------------------------------------------------------------------------------
 Los montos e inventario se calcularon con un script auxiliar (local de la Persona 2) para
 que cuadren con los CHECK. Si hay que cambiar datos, pedírselo a la Persona 2, o editar
 con cuidado y verificar que las consultas del final sigan dando 0 filas.

 Se ejecuta DESPUÉS de 01_esquema.sql, sobre una base recién creada.

 Decisiones:
  * Los IDs se fuerzan con IDENTITY_INSERT para que coincidan con el contrato del equipo
    (estados, roles, métodos de pago) y para que el resto de inserts sea legible
    (p. ej. "producto 2" siempre es el mismo). Al apagar IDENTITY_INSERT, SQL Server sigue
    numerando después del ID más alto, así que los SP pueden insertar sin problema.
  * Todo va en UNA transacción con XACT_ABORT ON: si un solo INSERT falla (por un CHECK,
    UNIQUE o FK), se deshace todo y la base no queda con datos a medias.
  * Todos los datos son ficticios. Correos @example.com (dominio reservado para pruebas).
    Contraseña de todos los usuarios demo: Demo123!  (solo se guarda su hash bcrypt).

 Contenido:
  catálogos fijos · geografía (7 provincias) + tarifas de envío · 10 marcas · 10 categorías
  50 productos (+ imágenes e inventario) · 1 admin + 20 clientes con usuario y dirección
  5 promociones · 37 pedidos (3 cancelados) · 230 movimientos · 20 reseñas

 Estructura:
  Secciones 1-9  -> la tienda "normal": inventario inicial con cantidades redondas, un
                    reabastecimiento a mitad de año y pedidos que siguen el flujo real.
  Sección 10     -> CASOS DE PRUEBA, separados y comentados uno por uno (productos
                    agotados o bajo el mínimo, inactivos, promociones que se solapan).
                    Se arman como en la vida real: con AJUSTE de inventario y UPDATE.

 Reglas de montos (las mismas que debe usar sp_Pedido_Confirmar):
  * DETALLE_PEDIDO.descuento = descuento TOTAL de la línea (mejor promoción vigente × cantidad).
  * DETALLE_PEDIDO.subtotal  = cantidad × precioUnitario − descuento.
  * PEDIDO.subtotalPedido    = Σ cantidad × precioUnitario   (antes de descuentos).
  * PEDIDO.descuentoPedido   = Σ descuentos de las líneas.
  * PEDIDO.costoEnvio        = TARIFA_ENVIO de la provincia de la dirección.
  * PEDIDO.totalPedido       = subtotalPedido − descuentoPedido + costoEnvio.
==========================================================================================
*/
USE tiendaDeportiva1;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;   -- cualquier error deshace la transacción completa

-- Protección: este script es para una base VACÍA. Si ya tiene datos, no hace nada.
IF EXISTS (SELECT 1 FROM ROL)
    THROW 50199, 'La base ya tiene datos. Borre y cree la base con 01_esquema.sql antes de correr 02_datos.sql.', 1;

BEGIN TRAN;

-- ======================== 1. CATÁLOGOS FIJOS (contrato del equipo) ========================

SET IDENTITY_INSERT ROL ON;
INSERT INTO ROL (idRol, nombreRol, descripcionRol) VALUES
    (1, N'Administrador', N'Gestiona catálogos, inventario, pedidos y reportes'),
    (2, N'Cliente', N'Compra en la tienda en línea');
SET IDENTITY_INSERT ROL OFF;

SET IDENTITY_INSERT ESTADO_CARRITO ON;
INSERT INTO ESTADO_CARRITO (idEstadoCarrito, nombreEstado) VALUES
    (1, N'Activo'),
    (2, N'Abandonado'),
    (3, N'Convertido');
SET IDENTITY_INSERT ESTADO_CARRITO OFF;

SET IDENTITY_INSERT ESTADO_PEDIDO ON;
INSERT INTO ESTADO_PEDIDO (idEstadoPedido, nombreEstado) VALUES
    (1, N'Pendiente'),
    (2, N'Confirmado'),
    (3, N'En preparación'),
    (4, N'Enviado'),
    (5, N'Entregado'),
    (6, N'Cancelado');
SET IDENTITY_INSERT ESTADO_PEDIDO OFF;

SET IDENTITY_INSERT ESTADO_PAGO ON;
INSERT INTO ESTADO_PAGO (idEstadoPago, nombreEstado) VALUES
    (1, N'Pendiente'),
    (2, N'Aprobado'),
    (3, N'Rechazado'),
    (4, N'Reembolsado');
SET IDENTITY_INSERT ESTADO_PAGO OFF;

SET IDENTITY_INSERT ESTADO_ENVIO ON;
INSERT INTO ESTADO_ENVIO (idEstadoEnvio, nombreEstado) VALUES
    (1, N'Pendiente'),
    (2, N'En tránsito'),
    (3, N'Entregado');
SET IDENTITY_INSERT ESTADO_ENVIO OFF;

-- Cambios de estado permitidos del pedido: 1→2, 1→6, 2→3, 2→6, 3→4, 3→6, 4→5
INSERT INTO TRANSICION_ESTADO (idEstadoOrigen, idEstadoDestino) VALUES
    (1, 2),
    (1, 6),
    (2, 3),
    (2, 6),
    (3, 4),
    (3, 6),
    (4, 5);

SET IDENTITY_INSERT METODO_PAGO ON;
INSERT INTO METODO_PAGO (idMetodoPago, nombreMetodo, descripcionMetodo) VALUES
    (1, N'Tarjeta (simulada)', N'Pago con tarjeta simulado, no se cobra de verdad'),
    (2, N'SINPE (simulado)', N'Transferencia SINPE Móvil simulada'),
    (3, N'Contra entrega', N'Se paga al recibir el pedido');
SET IDENTITY_INSERT METODO_PAGO OFF;

-- ======================== 2. GEOGRAFÍA Y TARIFAS DE ENVÍO ========================

SET IDENTITY_INSERT PAIS ON;
INSERT INTO PAIS (idPais, nombrePais) VALUES
    (1, N'Costa Rica');
SET IDENTITY_INSERT PAIS OFF;

SET IDENTITY_INSERT PROVINCIA ON;
INSERT INTO PROVINCIA (idProvincia, idPais, nombreProvincia) VALUES
    (1, 1, N'San José'),
    (2, 1, N'Alajuela'),
    (3, 1, N'Cartago'),
    (4, 1, N'Heredia'),
    (5, 1, N'Guanacaste'),
    (6, 1, N'Puntarenas'),
    (7, 1, N'Limón');
SET IDENTITY_INSERT PROVINCIA OFF;

SET IDENTITY_INSERT CANTON ON;
INSERT INTO CANTON (idCanton, idProvincia, nombreCanton) VALUES
    (1, 1, N'San José'),
    (2, 1, N'Escazú'),
    (3, 2, N'Alajuela'),
    (4, 2, N'San Ramón'),
    (5, 3, N'Cartago'),
    (6, 3, N'La Unión'),
    (7, 4, N'Heredia'),
    (8, 4, N'Santo Domingo'),
    (9, 5, N'Liberia'),
    (10, 5, N'Nicoya'),
    (11, 6, N'Puntarenas'),
    (12, 6, N'Garabito'),
    (13, 7, N'Limón'),
    (14, 7, N'Pococí');
SET IDENTITY_INSERT CANTON OFF;

SET IDENTITY_INSERT DISTRITO ON;
INSERT INTO DISTRITO (idDistrito, idCanton, nombreDistrito) VALUES
    (1, 1, N'Carmen'),
    (2, 1, N'Merced'),
    (3, 2, N'San Rafael'),
    (4, 3, N'Alajuela'),
    (5, 4, N'San Ramón'),
    (6, 5, N'Oriental'),
    (7, 5, N'Occidental'),
    (8, 6, N'Tres Ríos'),
    (9, 7, N'Heredia'),
    (10, 8, N'Santo Domingo'),
    (11, 9, N'Liberia'),
    (12, 10, N'Nicoya'),
    (13, 11, N'Puntarenas'),
    (14, 12, N'Jacó'),
    (15, 13, N'Limón'),
    (16, 14, N'Guápiles');
SET IDENTITY_INSERT DISTRITO OFF;

-- Una tarifa por provincia (colones)
SET IDENTITY_INSERT TARIFA_ENVIO ON;
INSERT INTO TARIFA_ENVIO (idTarifaEnvio, idProvincia, costoEnvio) VALUES
    (1, 1, 2500.00),
    (2, 2, 3000.00),
    (3, 3, 3000.00),
    (4, 4, 2500.00),
    (5, 5, 4000.00),
    (6, 6, 4000.00),
    (7, 7, 4500.00);
SET IDENTITY_INSERT TARIFA_ENVIO OFF;

-- ======================== 3. MARCAS, CATEGORÍAS Y PRODUCTOS ========================

SET IDENTITY_INSERT MARCA ON;
INSERT INTO MARCA (idMarca, nombreMarca, descripcionMarca) VALUES
    (1, N'Nike', N'Productos oficiales Nike'),
    (2, N'Adidas', N'Productos oficiales Adidas'),
    (3, N'Puma', N'Productos oficiales Puma'),
    (4, N'Under Armour', N'Productos oficiales Under Armour'),
    (5, N'Wilson', N'Productos oficiales Wilson'),
    (6, N'Spalding', N'Productos oficiales Spalding'),
    (7, N'Mizuno', N'Productos oficiales Mizuno'),
    (8, N'Asics', N'Productos oficiales Asics'),
    (9, N'New Balance', N'Productos oficiales New Balance'),
    (10, N'Reebok', N'Productos oficiales Reebok');
SET IDENTITY_INSERT MARCA OFF;

SET IDENTITY_INSERT CATEGORIA ON;
INSERT INTO CATEGORIA (idCategoria, nombreCategoria, descripcionCategoria) VALUES
    (1, N'Calzado', N'Tenis y zapatos deportivos'),
    (2, N'Ropa', N'Camisetas, pantalones y sudaderas'),
    (3, N'Balones', N'Balones de fútbol, baloncesto y voleibol'),
    (4, N'Raquetas', N'Tenis y pádel'),
    (5, N'Fitness', N'Equipo para entrenar en casa o en el gimnasio'),
    (6, N'Ciclismo', N'Ropa y accesorios para ciclismo'),
    (7, N'Natación', N'Equipo para nadar'),
    (8, N'Accesorios', N'Mochilas, gorras, medias y más'),
    (9, N'Camping', N'Senderismo y aire libre'),
    (10, N'Suplementos', N'Hidratación y nutrición deportiva');
SET IDENTITY_INSERT CATEGORIA OFF;

-- costo < precio en todos (si no, la utilidad del R7 sería negativa)
SET IDENTITY_INSERT PRODUCTO ON;
INSERT INTO PRODUCTO (idProducto, idMarca, idCategoria, sku, nombreProducto, descripcionProducto, precioProducto, costoProducto, stockMinimo, activo) VALUES
    (1, 1, 1, N'CAL-NIK-001', N'Tenis de correr Nike Pegasus', N'Tenis de correr Nike Pegasus. Producto original con garantía de 3 meses.', 79900.00, 46000.00, 5, 1),
    (2, 2, 1, N'CAL-ADI-002', N'Tenis de correr Adidas Ultraboost', N'Tenis de correr Adidas Ultraboost. Producto original con garantía de 3 meses.', 89900.00, 52000.00, 5, 1),
    (3, 8, 1, N'CAL-ASI-003', N'Tenis de correr Asics Gel-Kayano', N'Tenis de correr Asics Gel-Kayano. Producto original con garantía de 3 meses.', 84900.00, 49000.00, 5, 1),
    (4, 9, 1, N'CAL-NBA-004', N'Tenis New Balance Fresh Foam', N'Tenis New Balance Fresh Foam. Producto original con garantía de 3 meses.', 82900.00, 47500.00, 5, 1),
    (5, 7, 1, N'CAL-MIZ-005', N'Tenis Mizuno Wave Rider', N'Tenis Mizuno Wave Rider. Producto original con garantía de 3 meses.', 74900.00, 43000.00, 5, 1),
    (6, 1, 2, N'ROP-NIK-006', N'Camiseta Nike Dri-FIT', N'Camiseta Nike Dri-FIT. Producto original con garantía de 3 meses.', 19900.00, 9500.00, 10, 1),
    (7, 2, 2, N'ROP-ADI-007', N'Pantalón Adidas Tiro', N'Pantalón Adidas Tiro. Producto original con garantía de 3 meses.', 27900.00, 14000.00, 10, 1),
    (8, 4, 2, N'ROP-UAR-008', N'Licra Under Armour HeatGear', N'Licra Under Armour HeatGear. Producto original con garantía de 3 meses.', 24900.00, 12500.00, 10, 1),
    (9, 3, 2, N'ROP-PUM-009', N'Sudadera Puma Essentials', N'Sudadera Puma Essentials. Producto original con garantía de 3 meses.', 32900.00, 17000.00, 8, 1),
    (10, 10, 2, N'ROP-REE-010', N'Short Reebok Workout', N'Short Reebok Workout. Producto original con garantía de 3 meses.', 15900.00, 7500.00, 10, 1),
    (11, 2, 3, N'BAL-ADI-011', N'Balón de fútbol Adidas N.º 5', N'Balón de fútbol Adidas N.º 5. Producto original con garantía de 3 meses.', 18900.00, 9000.00, 8, 1),
    (12, 1, 3, N'BAL-NIK-012', N'Balón de fútbol Nike Strike', N'Balón de fútbol Nike Strike. Producto original con garantía de 3 meses.', 16900.00, 8200.00, 8, 1),
    (13, 6, 3, N'BAL-SPA-013', N'Balón de baloncesto Spalding TF', N'Balón de baloncesto Spalding TF. Producto original con garantía de 3 meses.', 34900.00, 18500.00, 6, 1),
    (14, 5, 3, N'BAL-WIL-014', N'Balón de baloncesto Wilson Evolution', N'Balón de baloncesto Wilson Evolution. Producto original con garantía de 3 meses.', 39900.00, 21000.00, 6, 1),
    (15, 7, 3, N'BAL-MIZ-015', N'Balón de voleibol Mizuno', N'Balón de voleibol Mizuno. Producto original con garantía de 3 meses.', 42900.00, 23000.00, 6, 1),
    (16, 5, 4, N'RAQ-WIL-016', N'Raqueta de tenis Wilson Clash 100', N'Raqueta de tenis Wilson Clash 100. Producto original con garantía de 3 meses.', 129900.00, 78000.00, 3, 1),
    (17, 5, 4, N'RAQ-WIL-017', N'Raqueta de tenis Wilson Pro Staff', N'Raqueta de tenis Wilson Pro Staff. Producto original con garantía de 3 meses.', 139900.00, 84000.00, 3, 1),
    (18, 2, 4, N'RAQ-ADI-018', N'Pala de pádel Adidas Metalbone', N'Pala de pádel Adidas Metalbone. Producto original con garantía de 3 meses.', 119900.00, 70000.00, 3, 1),
    (19, 5, 4, N'RAQ-WIL-019', N'Raqueta de tenis Wilson Ultra 100', N'Raqueta de tenis Wilson Ultra 100. Producto original con garantía de 3 meses.', 109900.00, 64000.00, 3, 1),
    (20, 2, 4, N'RAQ-ADI-020', N'Pala de pádel Adidas Match', N'Pala de pádel Adidas Match. Producto original con garantía de 3 meses.', 54900.00, 30000.00, 4, 1),
    (21, 10, 5, N'FIT-REE-021', N'Par de mancuernas Reebok 5 kg', N'Par de mancuernas Reebok 5 kg. Producto original con garantía de 3 meses.', 24900.00, 13000.00, 6, 1),
    (22, 1, 5, N'FIT-NIK-022', N'Esterilla de yoga Nike', N'Esterilla de yoga Nike. Producto original con garantía de 3 meses.', 22900.00, 11000.00, 6, 1),
    (23, 2, 5, N'FIT-ADI-023', N'Set de bandas de resistencia Adidas', N'Set de bandas de resistencia Adidas. Producto original con garantía de 3 meses.', 12900.00, 5800.00, 8, 1),
    (24, 10, 5, N'FIT-REE-024', N'Step de entrenamiento Reebok', N'Step de entrenamiento Reebok. Producto original con garantía de 3 meses.', 34900.00, 18000.00, 4, 1),
    (25, 4, 5, N'FIT-UAR-025', N'Cuerda para saltar Under Armour', N'Cuerda para saltar Under Armour. Producto original con garantía de 3 meses.', 9900.00, 4200.00, 10, 1),
    (26, 4, 6, N'CIC-UAR-026', N'Guantes de ciclismo Under Armour', N'Guantes de ciclismo Under Armour. Producto original con garantía de 3 meses.', 14900.00, 7000.00, 8, 1),
    (27, 2, 6, N'CIC-ADI-027', N'Culotte de ciclismo Adidas', N'Culotte de ciclismo Adidas. Producto original con garantía de 3 meses.', 29900.00, 15500.00, 6, 1),
    (28, 3, 6, N'CIC-PUM-028', N'Maillot de ciclismo Puma', N'Maillot de ciclismo Puma. Producto original con garantía de 3 meses.', 27900.00, 14000.00, 6, 1),
    (29, 1, 6, N'CIC-NIK-029', N'Botella de ciclismo Nike 700 ml', N'Botella de ciclismo Nike 700 ml. Producto original con garantía de 3 meses.', 11900.00, 5000.00, 10, 1),
    (30, 2, 6, N'CIC-ADI-030', N'Gafas de ciclismo Adidas', N'Gafas de ciclismo Adidas. Producto original con garantía de 3 meses.', 39900.00, 21000.00, 4, 1),
    (31, 1, 7, N'NAT-NIK-031', N'Gafas de natación Nike', N'Gafas de natación Nike. Producto original con garantía de 3 meses.', 12900.00, 5600.00, 10, 1),
    (32, 2, 7, N'NAT-ADI-032', N'Traje de baño Adidas', N'Traje de baño Adidas. Producto original con garantía de 3 meses.', 24900.00, 12000.00, 6, 1),
    (33, 1, 7, N'NAT-NIK-033', N'Gorro de natación Nike', N'Gorro de natación Nike. Producto original con garantía de 3 meses.', 6900.00, 2800.00, 12, 1),
    (34, 3, 7, N'NAT-PUM-034', N'Toalla de microfibra Puma', N'Toalla de microfibra Puma. Producto original con garantía de 3 meses.', 14900.00, 6900.00, 8, 1),
    (35, 1, 7, N'NAT-NIK-035', N'Tabla de natación Nike', N'Tabla de natación Nike. Producto original con garantía de 3 meses.', 11900.00, 5500.00, 6, 1),
    (36, 1, 8, N'ACC-NIK-036', N'Mochila Nike Brasilia', N'Mochila Nike Brasilia. Producto original con garantía de 3 meses.', 27900.00, 14500.00, 6, 1),
    (37, 2, 8, N'ACC-ADI-037', N'Paquete de 3 medias Adidas', N'Paquete de 3 medias Adidas. Producto original con garantía de 3 meses.', 8900.00, 3900.00, 15, 1),
    (38, 4, 8, N'ACC-UAR-038', N'Gorra Under Armour', N'Gorra Under Armour. Producto original con garantía de 3 meses.', 15900.00, 7200.00, 8, 1),
    (39, 3, 8, N'ACC-PUM-039', N'Bolso deportivo Puma', N'Bolso deportivo Puma. Producto original con garantía de 3 meses.', 29900.00, 15000.00, 5, 1),
    (40, 9, 8, N'ACC-NBA-040', N'Muñequeras New Balance', N'Muñequeras New Balance. Producto original con garantía de 3 meses.', 5900.00, 2300.00, 15, 1),
    (41, 4, 9, N'CAM-UAR-041', N'Mochila de senderismo Under Armour 30 L', N'Mochila de senderismo Under Armour 30 L. Producto original con garantía de 3 meses.', 49900.00, 27000.00, 4, 1),
    (42, 2, 9, N'CAM-ADI-042', N'Botas de senderismo Adidas Terrex', N'Botas de senderismo Adidas Terrex. Producto original con garantía de 3 meses.', 89900.00, 52000.00, 3, 1),
    (43, 10, 9, N'CAM-REE-043', N'Chaqueta impermeable Reebok', N'Chaqueta impermeable Reebok. Producto original con garantía de 3 meses.', 45900.00, 25000.00, 4, 1),
    (44, 2, 9, N'CAM-ADI-044', N'Termo Adidas 1 L', N'Termo Adidas 1 L. Producto original con garantía de 3 meses.', 19900.00, 9800.00, 6, 1),
    (45, 9, 9, N'CAM-NBA-045', N'Gorra de trekking New Balance', N'Gorra de trekking New Balance. Producto original con garantía de 3 meses.', 13900.00, 6300.00, 6, 1),
    (46, 4, 10, N'SUP-UAR-046', N'Bebida isotónica Under Armour (12 un.)', N'Bebida isotónica Under Armour (12 un.). Producto original con garantía de 3 meses.', 12900.00, 7400.00, 10, 1),
    (47, 1, 10, N'SUP-NIK-047', N'Barras energéticas Nike (6 un.)', N'Barras energéticas Nike (6 un.). Producto original con garantía de 3 meses.', 7900.00, 4100.00, 12, 1),
    (48, 2, 10, N'SUP-ADI-048', N'Proteína en polvo Adidas 1 kg', N'Proteína en polvo Adidas 1 kg. Producto original con garantía de 3 meses.', 34900.00, 21000.00, 5, 1),
    (49, 10, 10, N'SUP-REE-049', N'Electrolitos en sobres Reebok (20 un.)', N'Electrolitos en sobres Reebok (20 un.). Producto original con garantía de 3 meses.', 9900.00, 5200.00, 10, 1),
    (50, 3, 10, N'SUP-PUM-050', N'Gel energético Puma (10 un.)', N'Gel energético Puma (10 un.). Producto original con garantía de 3 meses.', 11900.00, 6600.00, 10, 1);
SET IDENTITY_INSERT PRODUCTO OFF;

-- Una imagen principal por producto (regla que controla el SP) y algunas secundarias
SET IDENTITY_INSERT IMAGEN_PRODUCTO ON;
INSERT INTO IMAGEN_PRODUCTO (idImagen, idProducto, urlImagen, esPrincipal) VALUES
    (1, 1, N'https://picsum.photos/seed/CAL-NIK-001/600/600', 1),
    (2, 2, N'https://picsum.photos/seed/CAL-ADI-002/600/600', 1),
    (3, 3, N'https://picsum.photos/seed/CAL-ASI-003/600/600', 1),
    (4, 4, N'https://picsum.photos/seed/CAL-NBA-004/600/600', 1),
    (5, 5, N'https://picsum.photos/seed/CAL-MIZ-005/600/600', 1),
    (6, 5, N'https://picsum.photos/seed/CAL-MIZ-005-2/600/600', 0),
    (7, 6, N'https://picsum.photos/seed/ROP-NIK-006/600/600', 1),
    (8, 7, N'https://picsum.photos/seed/ROP-ADI-007/600/600', 1),
    (9, 8, N'https://picsum.photos/seed/ROP-UAR-008/600/600', 1),
    (10, 9, N'https://picsum.photos/seed/ROP-PUM-009/600/600', 1),
    (11, 10, N'https://picsum.photos/seed/ROP-REE-010/600/600', 1),
    (12, 10, N'https://picsum.photos/seed/ROP-REE-010-2/600/600', 0),
    (13, 11, N'https://picsum.photos/seed/BAL-ADI-011/600/600', 1),
    (14, 12, N'https://picsum.photos/seed/BAL-NIK-012/600/600', 1),
    (15, 13, N'https://picsum.photos/seed/BAL-SPA-013/600/600', 1),
    (16, 14, N'https://picsum.photos/seed/BAL-WIL-014/600/600', 1),
    (17, 15, N'https://picsum.photos/seed/BAL-MIZ-015/600/600', 1),
    (18, 15, N'https://picsum.photos/seed/BAL-MIZ-015-2/600/600', 0),
    (19, 16, N'https://picsum.photos/seed/RAQ-WIL-016/600/600', 1),
    (20, 17, N'https://picsum.photos/seed/RAQ-WIL-017/600/600', 1),
    (21, 18, N'https://picsum.photos/seed/RAQ-ADI-018/600/600', 1),
    (22, 19, N'https://picsum.photos/seed/RAQ-WIL-019/600/600', 1),
    (23, 20, N'https://picsum.photos/seed/RAQ-ADI-020/600/600', 1),
    (24, 20, N'https://picsum.photos/seed/RAQ-ADI-020-2/600/600', 0),
    (25, 21, N'https://picsum.photos/seed/FIT-REE-021/600/600', 1),
    (26, 22, N'https://picsum.photos/seed/FIT-NIK-022/600/600', 1),
    (27, 23, N'https://picsum.photos/seed/FIT-ADI-023/600/600', 1),
    (28, 24, N'https://picsum.photos/seed/FIT-REE-024/600/600', 1),
    (29, 25, N'https://picsum.photos/seed/FIT-UAR-025/600/600', 1),
    (30, 25, N'https://picsum.photos/seed/FIT-UAR-025-2/600/600', 0),
    (31, 26, N'https://picsum.photos/seed/CIC-UAR-026/600/600', 1),
    (32, 27, N'https://picsum.photos/seed/CIC-ADI-027/600/600', 1),
    (33, 28, N'https://picsum.photos/seed/CIC-PUM-028/600/600', 1),
    (34, 29, N'https://picsum.photos/seed/CIC-NIK-029/600/600', 1),
    (35, 30, N'https://picsum.photos/seed/CIC-ADI-030/600/600', 1),
    (36, 30, N'https://picsum.photos/seed/CIC-ADI-030-2/600/600', 0),
    (37, 31, N'https://picsum.photos/seed/NAT-NIK-031/600/600', 1),
    (38, 32, N'https://picsum.photos/seed/NAT-ADI-032/600/600', 1),
    (39, 33, N'https://picsum.photos/seed/NAT-NIK-033/600/600', 1),
    (40, 34, N'https://picsum.photos/seed/NAT-PUM-034/600/600', 1),
    (41, 35, N'https://picsum.photos/seed/NAT-NIK-035/600/600', 1),
    (42, 35, N'https://picsum.photos/seed/NAT-NIK-035-2/600/600', 0),
    (43, 36, N'https://picsum.photos/seed/ACC-NIK-036/600/600', 1),
    (44, 37, N'https://picsum.photos/seed/ACC-ADI-037/600/600', 1),
    (45, 38, N'https://picsum.photos/seed/ACC-UAR-038/600/600', 1),
    (46, 39, N'https://picsum.photos/seed/ACC-PUM-039/600/600', 1),
    (47, 40, N'https://picsum.photos/seed/ACC-NBA-040/600/600', 1),
    (48, 40, N'https://picsum.photos/seed/ACC-NBA-040-2/600/600', 0),
    (49, 41, N'https://picsum.photos/seed/CAM-UAR-041/600/600', 1),
    (50, 42, N'https://picsum.photos/seed/CAM-ADI-042/600/600', 1),
    (51, 43, N'https://picsum.photos/seed/CAM-REE-043/600/600', 1),
    (52, 44, N'https://picsum.photos/seed/CAM-ADI-044/600/600', 1),
    (53, 45, N'https://picsum.photos/seed/CAM-NBA-045/600/600', 1),
    (54, 45, N'https://picsum.photos/seed/CAM-NBA-045-2/600/600', 0),
    (55, 46, N'https://picsum.photos/seed/SUP-UAR-046/600/600', 1),
    (56, 47, N'https://picsum.photos/seed/SUP-NIK-047/600/600', 1),
    (57, 48, N'https://picsum.photos/seed/SUP-ADI-048/600/600', 1),
    (58, 49, N'https://picsum.photos/seed/SUP-REE-049/600/600', 1),
    (59, 50, N'https://picsum.photos/seed/SUP-PUM-050/600/600', 1),
    (60, 50, N'https://picsum.photos/seed/SUP-PUM-050-2/600/600', 0);
SET IDENTITY_INSERT IMAGEN_PRODUCTO OFF;

-- ======================== 4. CLIENTES, USUARIOS Y DIRECCIONES ========================

SET IDENTITY_INSERT CLIENTE ON;
INSERT INTO CLIENTE (idCliente, nombreCliente, apellidoCliente, correoCliente, telefonoCliente, fechaRegistro, activo) VALUES
    (1, N'Ana', N'Mora Vargas', N'ana.mora@example.com', N'8800-0001', '2025-02-04T09:00:00', 1),
    (2, N'Luis', N'Solano Rojas', N'luis.solano@example.com', N'8800-0002', '2025-03-07T09:00:00', 1),
    (3, N'María', N'Jiménez Castro', N'maria.jimenez@example.com', N'8800-0003', '2025-04-10T09:00:00', 1),
    (4, N'Carlos', N'Araya Quesada', N'carlos.araya@example.com', N'8800-0004', '2025-05-13T09:00:00', 1),
    (5, N'Sofía', N'Vargas Chaves', N'sofia.vargas@example.com', N'8800-0005', '2025-06-16T09:00:00', 1),
    (6, N'Diego', N'Rojas Monge', N'diego.rojas@example.com', N'8800-0006', '2025-07-19T09:00:00', 1),
    (7, N'Valeria', N'Castro Núñez', N'valeria.castro@example.com', N'8800-0007', '2025-08-22T09:00:00', 1),
    (8, N'Andrés', N'Quesada Mora', N'andres.quesada@example.com', N'8800-0008', '2025-09-25T09:00:00', 1),
    (9, N'Camila', N'Chaves Salas', N'camila.chaves@example.com', N'8800-0009', '2025-10-01T09:00:00', 1),
    (10, N'José', N'Monge Alfaro', N'jose.monge@example.com', N'8800-0010', '2025-11-04T09:00:00', 1),
    (11, N'Daniela', N'Núñez Brenes', N'daniela.nuñez@example.com', N'8800-0011', '2025-12-07T09:00:00', 1),
    (12, N'Pablo', N'Salas Ureña', N'pablo.salas@example.com', N'8800-0012', '2025-01-10T09:00:00', 1),
    (13, N'Fernanda', N'Alfaro Cordero', N'fernanda.alfaro@example.com', N'8800-0013', '2025-02-13T09:00:00', 1),
    (14, N'Mateo', N'Brenes Arias', N'mateo.brenes@example.com', N'8800-0014', '2025-03-16T09:00:00', 1),
    (15, N'Isabel', N'Ureña Soto', N'isabel.ureña@example.com', N'8800-0015', '2025-04-19T09:00:00', 1),
    (16, N'Ricardo', N'Cordero Vega', N'ricardo.cordero@example.com', N'8800-0016', '2025-05-22T09:00:00', 1),
    (17, N'Gabriela', N'Arias Campos', N'gabriela.arias@example.com', N'8800-0017', '2025-06-25T09:00:00', 1),
    (18, N'Esteban', N'Soto Mena', N'esteban.soto@example.com', N'8800-0018', '2025-07-01T09:00:00', 1),
    (19, N'Natalia', N'Vega Rivera', N'natalia.vega@example.com', N'8800-0019', '2025-08-04T09:00:00', 1),
    (20, N'Tomás', N'Campos Herrera', N'tomas.campos@example.com', N'8800-0020', '2025-09-07T09:00:00', 1);
SET IDENTITY_INSERT CLIENTE OFF;

-- idUsuario 1 = admin (sin cliente). idUsuario = idCliente + 1 para los clientes.
-- Contraseña de todos: Demo123! (hash bcrypt, costo 10)
SET IDENTITY_INSERT USUARIO ON;
INSERT INTO USUARIO (idUsuario, idCliente, idRol, nombreUsuario, passwordHash, fechaCreacion) VALUES
    (1, NULL, 1, N'admin', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-01-01T08:00:00'),
    (2, 1, 2, N'ana.mora', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-02-04T09:00:00'),
    (3, 2, 2, N'luis.solano', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-03-07T09:00:00'),
    (4, 3, 2, N'maria.jimenez', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-04-10T09:00:00'),
    (5, 4, 2, N'carlos.araya', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-05-13T09:00:00'),
    (6, 5, 2, N'sofia.vargas', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-06-16T09:00:00'),
    (7, 6, 2, N'diego.rojas', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-07-19T09:00:00'),
    (8, 7, 2, N'valeria.castro', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-08-22T09:00:00'),
    (9, 8, 2, N'andres.quesada', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-09-25T09:00:00'),
    (10, 9, 2, N'camila.chaves', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-10-01T09:00:00'),
    (11, 10, 2, N'jose.monge', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-11-04T09:00:00'),
    (12, 11, 2, N'daniela.nuñez', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-12-07T09:00:00'),
    (13, 12, 2, N'pablo.salas', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-01-10T09:00:00'),
    (14, 13, 2, N'fernanda.alfaro', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-02-13T09:00:00'),
    (15, 14, 2, N'mateo.brenes', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-03-16T09:00:00'),
    (16, 15, 2, N'isabel.ureña', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-04-19T09:00:00'),
    (17, 16, 2, N'ricardo.cordero', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-05-22T09:00:00'),
    (18, 17, 2, N'gabriela.arias', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-06-25T09:00:00'),
    (19, 18, 2, N'esteban.soto', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-07-01T09:00:00'),
    (20, 19, 2, N'natalia.vega', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-08-04T09:00:00'),
    (21, 20, 2, N'tomas.campos', N'$2b$10$rxPOGcwA20u0Zr7ovgzO/.QozrEwq95uK7xB5M9zP9IFPQAysxLs6', '2025-09-07T09:00:00');
SET IDENTITY_INSERT USUARIO OFF;

SET IDENTITY_INSERT DIRECCION ON;
INSERT INTO DIRECCION (idDireccion, idCliente, idDistrito, otrasReferencia) VALUES
    (1, 1, 1, N'Frente a la escuela, casa esquinera'),
    (2, 1, 3, N'Costado sur de la iglesia'),
    (3, 2, 9, N'Del supermercado 200 m este'),
    (4, 3, 6, N'Condominio Las Flores, casa 12'),
    (5, 4, 4, N'Costado sur de la iglesia'),
    (6, 5, 3, N'Edificio Torres del Este, apto 4B'),
    (7, 5, 13, N'100 m norte del parque central'),
    (8, 6, 11, N'50 m oeste de la plaza de deportes'),
    (9, 7, 13, N'Casa color verde, portón negro'),
    (10, 8, 15, N'100 m norte del parque central'),
    (11, 9, 2, N'Frente a la escuela, casa esquinera'),
    (12, 9, 11, N'Costado sur de la iglesia'),
    (13, 10, 10, N'Del supermercado 200 m este'),
    (14, 11, 8, N'Condominio Las Flores, casa 12'),
    (15, 12, 5, N'Costado sur de la iglesia'),
    (16, 13, 14, N'Edificio Torres del Este, apto 4B'),
    (17, 14, 16, N'50 m oeste de la plaza de deportes'),
    (18, 15, 7, N'Casa color verde, portón negro'),
    (19, 16, 12, N'100 m norte del parque central'),
    (20, 17, 1, N'Frente a la escuela, casa esquinera'),
    (21, 18, 9, N'Del supermercado 200 m este'),
    (22, 19, 6, N'Condominio Las Flores, casa 12'),
    (23, 20, 4, N'Costado sur de la iglesia');
SET IDENTITY_INSERT DIRECCION OFF;

-- ======================== 5. PROMOCIONES ========================

-- 1-3 vencidas, 4 y 5 vigentes al 26-nov-2026
SET IDENTITY_INSERT PROMOCION ON;
INSERT INTO PROMOCION (idPromocion, nombrePromocion, descripcionPromocion, tipoDescuento, valorDescuento, fechaInicio, fechaFin) VALUES
    (1, N'Verano 2026', N'15 % en calzado para empezar el año', N'PORCENTAJE', 15.00, '2026-01-05T00:00:00', '2026-02-28T23:59:59'),
    (2, N'Regreso a clases', N'10 % en mochilas y accesorios', N'PORCENTAJE', 10.00, '2026-02-01T00:00:00', '2026-03-15T23:59:59'),
    (3, N'Día del Padre', N'₡5 000 menos en ropa seleccionada', N'MONTO', 5000.00, '2026-06-01T00:00:00', '2026-06-30T23:59:59'),
    (4, N'Black Friday 2026', N'25 % en productos seleccionados', N'PORCENTAJE', 25.00, '2026-11-20T00:00:00', '2026-11-30T23:59:59'),
    (5, N'Temporada de fútbol', N'12 % en balones de fútbol', N'PORCENTAJE', 12.00, '2026-11-01T00:00:00', '2026-12-31T23:59:59');
SET IDENTITY_INSERT PROMOCION OFF;

INSERT INTO PROMOCION_PRODUCTO (idPromocion, idProducto) VALUES
    (1, 1),
    (1, 2),
    (1, 3),
    (1, 4),
    (1, 5),
    (2, 36),
    (2, 37),
    (2, 38),
    (2, 39),
    (2, 40),
    (3, 6),
    (3, 7),
    (3, 8),
    (3, 9),
    (4, 1),
    (4, 16),
    (4, 21),
    (4, 36),
    (5, 11),
    (5, 12);

-- ======================== 6. INVENTARIO ========================

-- idInventario = idProducto.
-- cantidadDisponible = inicial + reabastecimiento − ventas + devoluciones
SET IDENTITY_INSERT INVENTARIO ON;
INSERT INTO INVENTARIO (idInventario, idProducto, cantidadDisponible, cantidadReservada, ultimaActualizacion) VALUES
    (1, 1, 33, 0, '2026-11-26T08:00:00'),
    (2, 2, 11, 0, '2026-11-26T08:00:00'),
    (3, 3, 17, 0, '2026-11-26T08:00:00'),
    (4, 4, 37, 0, '2026-11-26T08:00:00'),
    (5, 5, 34, 0, '2026-11-26T08:00:00'),
    (6, 6, 58, 0, '2026-11-26T08:00:00'),
    (7, 7, 31, 0, '2026-11-26T08:00:00'),
    (8, 8, 74, 0, '2026-11-26T08:00:00'),
    (9, 9, 36, 0, '2026-11-26T08:00:00'),
    (10, 10, 53, 0, '2026-11-26T08:00:00'),
    (11, 11, 55, 0, '2026-11-26T08:00:00'),
    (12, 12, 76, 0, '2026-11-26T08:00:00'),
    (13, 13, 39, 0, '2026-11-26T08:00:00'),
    (14, 14, 34, 0, '2026-11-26T08:00:00'),
    (15, 15, 29, 0, '2026-11-26T08:00:00'),
    (16, 16, 38, 0, '2026-11-26T08:00:00'),
    (17, 17, 9, 0, '2026-11-26T08:00:00'),
    (18, 18, 15, 0, '2026-11-26T08:00:00'),
    (19, 19, 20, 0, '2026-11-26T08:00:00'),
    (20, 20, 53, 0, '2026-11-26T08:00:00'),
    (21, 21, 51, 0, '2026-11-26T08:00:00'),
    (22, 22, 60, 0, '2026-11-26T08:00:00'),
    (23, 23, 51, 0, '2026-11-26T08:00:00'),
    (24, 24, 57, 0, '2026-11-26T08:00:00'),
    (25, 25, 55, 0, '2026-11-26T08:00:00'),
    (26, 26, 55, 0, '2026-11-26T08:00:00'),
    (27, 27, 39, 0, '2026-11-26T08:00:00'),
    (28, 28, 60, 0, '2026-11-26T08:00:00'),
    (29, 29, 49, 0, '2026-11-26T08:00:00'),
    (30, 30, 29, 0, '2026-11-26T08:00:00'),
    (31, 31, 52, 0, '2026-11-26T08:00:00'),
    (32, 32, 74, 0, '2026-11-26T08:00:00'),
    (33, 33, 51, 0, '2026-11-26T08:00:00'),
    (34, 34, 57, 0, '2026-11-26T08:00:00'),
    (35, 35, 53, 0, '2026-11-26T08:00:00'),
    (36, 36, 51, 0, '2026-11-26T08:00:00'),
    (37, 37, 55, 0, '2026-11-26T08:00:00'),
    (38, 38, 55, 0, '2026-11-26T08:00:00'),
    (39, 39, 34, 0, '2026-11-26T08:00:00'),
    (40, 40, 77, 0, '2026-11-26T08:00:00'),
    (41, 41, 35, 0, '2026-11-26T08:00:00'),
    (42, 42, 8, 0, '2026-11-26T08:00:00'),
    (43, 43, 34, 0, '2026-11-26T08:00:00'),
    (44, 44, 69, 0, '2026-11-26T08:00:00'),
    (45, 45, 54, 0, '2026-11-26T08:00:00'),
    (46, 46, 47, 0, '2026-11-26T08:00:00'),
    (47, 47, 49, 0, '2026-11-26T08:00:00'),
    (48, 48, 55, 0, '2026-11-26T08:00:00'),
    (49, 49, 55, 0, '2026-11-26T08:00:00'),
    (50, 50, 53, 0, '2026-11-26T08:00:00');
SET IDENTITY_INSERT INVENTARIO OFF;

-- ======================== 7. PEDIDOS ========================

SET IDENTITY_INSERT PEDIDO ON;
INSERT INTO PEDIDO (idPedido, idCliente, idDireccion, idEstadoPedido, fechaPedido, subtotalPedido, descuentoPedido, costoEnvio, totalPedido) VALUES
    (1, 1, 2, 5, '2026-01-01T09:00:00', 95400.00, 0.00, 2500.00, 97900.00),
    (2, 2, 3, 5, '2026-01-08T10:13:00', 218400.00, 0.00, 2500.00, 220900.00),
    (3, 3, 4, 5, '2026-01-15T11:26:00', 428900.00, 0.00, 3000.00, 431900.00),
    (4, 5, 6, 5, '2026-02-04T13:52:00', 39800.00, 0.00, 2500.00, 42300.00),
    (5, 6, 8, 5, '2026-02-11T14:05:00', 640500.00, 0.00, 4000.00, 644500.00),
    (6, 4, 5, 5, '2026-02-22T12:39:00', 79600.00, 5580.00, 3000.00, 77020.00),
    (7, 9, 12, 5, '2026-03-07T17:44:00', 794300.00, 1780.00, 4000.00, 796520.00),
    (8, 1, 1, 6, '2026-03-14T10:15:00', 97500.00, 0.00, 2500.00, 100000.00),
    (9, 7, 9, 5, '2026-03-18T15:18:00', 542700.00, 0.00, 4000.00, 546700.00),
    (10, 8, 10, 5, '2026-03-25T16:31:00', 37600.00, 0.00, 4500.00, 42100.00),
    (11, 12, 15, 5, '2026-04-03T11:23:00', 217200.00, 0.00, 3000.00, 220200.00),
    (12, 10, 13, 5, '2026-04-14T09:57:00', 742200.00, 0.00, 2500.00, 744700.00),
    (13, 11, 14, 5, '2026-04-21T10:10:00', 656000.00, 0.00, 3000.00, 659000.00),
    (14, 13, 16, 5, '2026-05-10T12:36:00', 229900.00, 0.00, 4000.00, 233900.00),
    (15, 14, 17, 5, '2026-05-17T13:49:00', 287900.00, 0.00, 4500.00, 292400.00),
    (16, 15, 18, 5, '2026-05-24T14:02:00', 629900.00, 0.00, 3000.00, 632900.00),
    (17, 1, 2, 5, '2026-06-06T15:15:00', 275400.00, 0.00, 2500.00, 277900.00),
    (18, 2, 3, 5, '2026-06-13T16:28:00', 40800.00, 0.00, 2500.00, 43300.00),
    (19, 3, 4, 5, '2026-06-20T17:41:00', 29700.00, 0.00, 3000.00, 32700.00),
    (20, 4, 5, 5, '2026-07-02T09:54:00', 301800.00, 0.00, 3000.00, 304800.00),
    (21, 5, 7, 5, '2026-07-09T10:07:00', 339200.00, 0.00, 4000.00, 343200.00),
    (22, 2, 3, 6, '2026-07-09T16:30:00', 148500.00, 0.00, 2500.00, 151000.00),
    (23, 6, 8, 5, '2026-07-16T11:20:00', 403200.00, 0.00, 4000.00, 407200.00),
    (24, 8, 10, 5, '2026-08-05T13:46:00', 269700.00, 0.00, 4500.00, 274200.00),
    (25, 9, 12, 5, '2026-08-12T14:59:00', 416300.00, 0.00, 4000.00, 420300.00),
    (26, 7, 9, 5, '2026-08-23T12:33:00', 355900.00, 0.00, 4000.00, 359900.00),
    (27, 11, 14, 5, '2026-09-01T16:25:00', 269700.00, 0.00, 3000.00, 272700.00),
    (28, 12, 15, 5, '2026-09-08T17:38:00', 35700.00, 0.00, 3000.00, 38700.00),
    (29, 10, 13, 5, '2026-09-19T15:12:00', 201200.00, 0.00, 2500.00, 203700.00),
    (30, 15, 18, 5, '2026-10-04T11:17:00', 163400.00, 0.00, 3000.00, 166400.00),
    (31, 13, 16, 5, '2026-10-15T09:51:00', 516700.00, 0.00, 4000.00, 520700.00),
    (32, 14, 17, 5, '2026-10-22T10:04:00', 715300.00, 0.00, 4500.00, 719800.00),
    (33, 7, 9, 5, '2026-11-03T15:20:00', 275200.00, 6804.00, 4000.00, 272396.00),
    (34, 3, 4, 6, '2026-11-18T12:45:00', 251000.00, 0.00, 3000.00, 254000.00),
    (35, 4, 5, 4, '2026-11-21T10:05:00', 383300.00, 13950.00, 3000.00, 372350.00),
    (36, 5, 6, 3, '2026-11-23T18:40:00', 288500.00, 0.00, 2500.00, 291000.00),
    (37, 6, 8, 2, '2026-11-25T11:10:00', 425300.00, 0.00, 4000.00, 429300.00);
SET IDENTITY_INSERT PEDIDO OFF;

-- Precio y costo del día de la compra (históricos)
SET IDENTITY_INSERT DETALLE_PEDIDO ON;
INSERT INTO DETALLE_PEDIDO (idDetallePedido, idPedido, idProducto, cantidad, precioUnitario, costoUnitario, descuento, subtotal) VALUES
    (1, 1, 21, 3, 24900.00, 13000.00, 0.00, 74700.00),
    (2, 1, 33, 3, 6900.00, 2800.00, 0.00, 20700.00),
    (3, 2, 15, 3, 42900.00, 23000.00, 0.00, 128700.00),
    (4, 2, 39, 3, 29900.00, 15000.00, 0.00, 89700.00),
    (5, 3, 37, 1, 8900.00, 3900.00, 0.00, 8900.00),
    (6, 3, 36, 3, 27900.00, 14500.00, 0.00, 83700.00),
    (7, 3, 47, 1, 7900.00, 4100.00, 0.00, 7900.00),
    (8, 3, 32, 1, 24900.00, 12000.00, 0.00, 24900.00),
    (9, 3, 38, 2, 15900.00, 7200.00, 0.00, 31800.00),
    (10, 3, 29, 1, 11900.00, 5000.00, 0.00, 11900.00),
    (11, 3, 16, 2, 129900.00, 78000.00, 0.00, 259800.00),
    (12, 4, 44, 2, 19900.00, 9800.00, 0.00, 39800.00),
    (13, 5, 14, 3, 39900.00, 21000.00, 0.00, 119700.00),
    (14, 5, 26, 3, 14900.00, 7000.00, 0.00, 44700.00),
    (15, 5, 17, 3, 139900.00, 84000.00, 0.00, 419700.00),
    (16, 5, 23, 1, 12900.00, 5800.00, 0.00, 12900.00),
    (17, 5, 47, 3, 7900.00, 4100.00, 0.00, 23700.00),
    (18, 5, 25, 2, 9900.00, 4200.00, 0.00, 19800.00),
    (19, 6, 36, 2, 27900.00, 14500.00, 5580.00, 50220.00),
    (20, 6, 35, 2, 11900.00, 5500.00, 0.00, 23800.00),
    (21, 7, 10, 2, 15900.00, 7500.00, 0.00, 31800.00),
    (22, 7, 42, 2, 89900.00, 52000.00, 0.00, 179800.00),
    (23, 7, 46, 2, 12900.00, 7400.00, 0.00, 25800.00),
    (24, 7, 48, 1, 34900.00, 21000.00, 0.00, 34900.00),
    (25, 7, 37, 2, 8900.00, 3900.00, 1780.00, 16020.00),
    (26, 7, 20, 3, 54900.00, 30000.00, 0.00, 164700.00),
    (27, 7, 2, 3, 89900.00, 52000.00, 0.00, 269700.00),
    (28, 7, 24, 2, 34900.00, 18000.00, 0.00, 69800.00),
    (29, 8, 28, 3, 27900.00, 14000.00, 0.00, 83700.00),
    (30, 8, 33, 2, 6900.00, 2800.00, 0.00, 13800.00),
    (31, 9, 34, 1, 14900.00, 6900.00, 0.00, 14900.00),
    (32, 9, 17, 3, 139900.00, 84000.00, 0.00, 419700.00),
    (33, 9, 27, 1, 29900.00, 15500.00, 0.00, 29900.00),
    (34, 9, 37, 1, 8900.00, 3900.00, 0.00, 8900.00),
    (35, 9, 31, 1, 12900.00, 5600.00, 0.00, 12900.00),
    (36, 9, 33, 3, 6900.00, 2800.00, 0.00, 20700.00),
    (37, 9, 50, 3, 11900.00, 6600.00, 0.00, 35700.00),
    (38, 10, 46, 2, 12900.00, 7400.00, 0.00, 25800.00),
    (39, 10, 40, 2, 5900.00, 2300.00, 0.00, 11800.00),
    (40, 11, 31, 3, 12900.00, 5600.00, 0.00, 38700.00),
    (41, 11, 15, 3, 42900.00, 23000.00, 0.00, 128700.00),
    (42, 11, 8, 2, 24900.00, 12500.00, 0.00, 49800.00),
    (43, 12, 46, 3, 12900.00, 7400.00, 0.00, 38700.00),
    (44, 12, 35, 3, 11900.00, 5500.00, 0.00, 35700.00),
    (45, 12, 17, 3, 139900.00, 84000.00, 0.00, 419700.00),
    (46, 12, 36, 2, 27900.00, 14500.00, 0.00, 55800.00),
    (47, 12, 26, 2, 14900.00, 7000.00, 0.00, 29800.00),
    (48, 12, 43, 2, 45900.00, 25000.00, 0.00, 91800.00),
    (49, 12, 20, 1, 54900.00, 30000.00, 0.00, 54900.00),
    (50, 12, 47, 2, 7900.00, 4100.00, 0.00, 15800.00),
    (51, 13, 1, 2, 79900.00, 46000.00, 0.00, 159800.00),
    (52, 13, 3, 3, 84900.00, 49000.00, 0.00, 254700.00),
    (53, 13, 10, 2, 15900.00, 7500.00, 0.00, 31800.00),
    (54, 13, 42, 2, 89900.00, 52000.00, 0.00, 179800.00),
    (55, 13, 39, 1, 29900.00, 15000.00, 0.00, 29900.00),
    (56, 14, 45, 2, 13900.00, 6300.00, 0.00, 27800.00),
    (57, 14, 32, 2, 24900.00, 12000.00, 0.00, 49800.00),
    (58, 14, 30, 3, 39900.00, 21000.00, 0.00, 119700.00),
    (59, 14, 33, 3, 6900.00, 2800.00, 0.00, 20700.00),
    (60, 14, 50, 1, 11900.00, 6600.00, 0.00, 11900.00),
    (61, 15, 21, 3, 24900.00, 13000.00, 0.00, 74700.00),
    (62, 15, 30, 3, 39900.00, 21000.00, 0.00, 119700.00),
    (63, 15, 7, 2, 27900.00, 14000.00, 0.00, 55800.00),
    (64, 15, 29, 2, 11900.00, 5000.00, 0.00, 23800.00),
    (65, 15, 45, 1, 13900.00, 6300.00, 0.00, 13900.00),
    (66, 16, 47, 1, 7900.00, 4100.00, 0.00, 7900.00),
    (67, 16, 31, 1, 12900.00, 5600.00, 0.00, 12900.00),
    (68, 16, 5, 3, 74900.00, 43000.00, 0.00, 224700.00),
    (69, 16, 42, 2, 89900.00, 52000.00, 0.00, 179800.00),
    (70, 16, 18, 1, 119900.00, 70000.00, 0.00, 119900.00),
    (71, 16, 32, 2, 24900.00, 12000.00, 0.00, 49800.00),
    (72, 16, 24, 1, 34900.00, 18000.00, 0.00, 34900.00),
    (73, 17, 1, 3, 79900.00, 46000.00, 0.00, 239700.00),
    (74, 17, 29, 3, 11900.00, 5000.00, 0.00, 35700.00),
    (75, 18, 40, 1, 5900.00, 2300.00, 0.00, 5900.00),
    (76, 18, 13, 1, 34900.00, 18500.00, 0.00, 34900.00),
    (77, 19, 49, 3, 9900.00, 5200.00, 0.00, 29700.00),
    (78, 20, 43, 1, 45900.00, 25000.00, 0.00, 45900.00),
    (79, 20, 49, 2, 9900.00, 5200.00, 0.00, 19800.00),
    (80, 20, 41, 3, 49900.00, 27000.00, 0.00, 149700.00),
    (81, 20, 23, 3, 12900.00, 5800.00, 0.00, 38700.00),
    (82, 20, 10, 3, 15900.00, 7500.00, 0.00, 47700.00),
    (83, 21, 45, 3, 13900.00, 6300.00, 0.00, 41700.00),
    (84, 21, 47, 3, 7900.00, 4100.00, 0.00, 23700.00),
    (85, 21, 9, 3, 32900.00, 17000.00, 0.00, 98700.00),
    (86, 21, 35, 2, 11900.00, 5500.00, 0.00, 23800.00),
    (87, 21, 15, 1, 42900.00, 23000.00, 0.00, 42900.00),
    (88, 21, 31, 2, 12900.00, 5600.00, 0.00, 25800.00),
    (89, 21, 38, 3, 15900.00, 7200.00, 0.00, 47700.00),
    (90, 21, 48, 1, 34900.00, 21000.00, 0.00, 34900.00),
    (91, 22, 38, 2, 15900.00, 7200.00, 0.00, 31800.00),
    (92, 22, 20, 2, 54900.00, 30000.00, 0.00, 109800.00),
    (93, 22, 33, 1, 6900.00, 2800.00, 0.00, 6900.00),
    (94, 23, 25, 1, 9900.00, 4200.00, 0.00, 9900.00),
    (95, 23, 1, 2, 79900.00, 46000.00, 0.00, 159800.00),
    (96, 23, 7, 3, 27900.00, 14000.00, 0.00, 83700.00),
    (97, 23, 5, 2, 74900.00, 43000.00, 0.00, 149800.00),
    (98, 24, 2, 3, 89900.00, 52000.00, 0.00, 269700.00),
    (99, 25, 21, 3, 24900.00, 13000.00, 0.00, 74700.00),
    (100, 25, 44, 3, 19900.00, 9800.00, 0.00, 59700.00),
    (101, 25, 20, 1, 54900.00, 30000.00, 0.00, 54900.00),
    (102, 25, 29, 1, 11900.00, 5000.00, 0.00, 11900.00),
    (103, 25, 50, 3, 11900.00, 6600.00, 0.00, 35700.00),
    (104, 25, 8, 3, 24900.00, 12500.00, 0.00, 74700.00),
    (105, 25, 32, 1, 24900.00, 12000.00, 0.00, 24900.00),
    (106, 25, 30, 2, 39900.00, 21000.00, 0.00, 79800.00),
    (107, 26, 30, 3, 39900.00, 21000.00, 0.00, 119700.00),
    (108, 26, 39, 2, 29900.00, 15000.00, 0.00, 59800.00),
    (109, 26, 15, 1, 42900.00, 23000.00, 0.00, 42900.00),
    (110, 26, 44, 1, 19900.00, 9800.00, 0.00, 19900.00),
    (111, 26, 46, 3, 12900.00, 7400.00, 0.00, 38700.00),
    (112, 26, 5, 1, 74900.00, 43000.00, 0.00, 74900.00),
    (113, 27, 42, 3, 89900.00, 52000.00, 0.00, 269700.00),
    (114, 28, 29, 3, 11900.00, 5000.00, 0.00, 35700.00),
    (115, 29, 31, 1, 12900.00, 5600.00, 0.00, 12900.00),
    (116, 29, 46, 3, 12900.00, 7400.00, 0.00, 38700.00),
    (117, 29, 44, 3, 19900.00, 9800.00, 0.00, 59700.00),
    (118, 29, 2, 1, 89900.00, 52000.00, 0.00, 89900.00),
    (119, 30, 11, 2, 18900.00, 9000.00, 0.00, 37800.00),
    (120, 30, 43, 2, 45900.00, 25000.00, 0.00, 91800.00),
    (121, 30, 12, 2, 16900.00, 8200.00, 0.00, 33800.00),
    (122, 31, 6, 2, 19900.00, 9500.00, 0.00, 39800.00),
    (123, 31, 25, 2, 9900.00, 4200.00, 0.00, 19800.00),
    (124, 31, 20, 2, 54900.00, 30000.00, 0.00, 109800.00),
    (125, 31, 12, 2, 16900.00, 8200.00, 0.00, 33800.00),
    (126, 31, 23, 2, 12900.00, 5800.00, 0.00, 25800.00),
    (127, 31, 47, 1, 7900.00, 4100.00, 0.00, 7900.00),
    (128, 31, 17, 2, 139900.00, 84000.00, 0.00, 279800.00),
    (129, 32, 29, 1, 11900.00, 5000.00, 0.00, 11900.00),
    (130, 32, 8, 1, 24900.00, 12500.00, 0.00, 24900.00),
    (131, 32, 34, 2, 14900.00, 6900.00, 0.00, 29800.00),
    (132, 32, 48, 3, 34900.00, 21000.00, 0.00, 104700.00),
    (133, 32, 18, 2, 119900.00, 70000.00, 0.00, 239800.00),
    (134, 32, 7, 2, 27900.00, 14000.00, 0.00, 55800.00),
    (135, 32, 14, 3, 39900.00, 21000.00, 0.00, 119700.00),
    (136, 32, 15, 3, 42900.00, 23000.00, 0.00, 128700.00),
    (137, 33, 2, 2, 89900.00, 52000.00, 0.00, 179800.00),
    (138, 33, 23, 3, 12900.00, 5800.00, 0.00, 38700.00),
    (139, 33, 11, 3, 18900.00, 9000.00, 6804.00, 49896.00),
    (140, 34, 8, 3, 24900.00, 12500.00, 0.00, 74700.00),
    (141, 34, 40, 3, 5900.00, 2300.00, 0.00, 17700.00),
    (142, 34, 46, 3, 12900.00, 7400.00, 0.00, 38700.00),
    (143, 34, 18, 1, 119900.00, 70000.00, 0.00, 119900.00),
    (144, 35, 37, 1, 8900.00, 3900.00, 0.00, 8900.00),
    (145, 35, 18, 2, 119900.00, 70000.00, 0.00, 239800.00),
    (146, 35, 43, 1, 45900.00, 25000.00, 0.00, 45900.00),
    (147, 35, 36, 2, 27900.00, 14500.00, 13950.00, 41850.00),
    (148, 35, 9, 1, 32900.00, 17000.00, 0.00, 32900.00),
    (149, 36, 44, 2, 19900.00, 9800.00, 0.00, 39800.00),
    (150, 36, 4, 3, 82900.00, 47500.00, 0.00, 248700.00),
    (151, 37, 42, 3, 89900.00, 52000.00, 0.00, 269700.00),
    (152, 37, 41, 2, 49900.00, 27000.00, 0.00, 99800.00),
    (153, 37, 7, 2, 27900.00, 14000.00, 0.00, 55800.00);
SET IDENTITY_INSERT DETALLE_PEDIDO OFF;

INSERT INTO PEDIDO_PROMOCION (idPedido, idPromocion) VALUES
    (6, 2),
    (7, 2),
    (33, 5),
    (35, 4);

-- Pago 2 = Aprobado; 4 = Reembolsado (pedidos cancelados)
SET IDENTITY_INSERT PAGO ON;
INSERT INTO PAGO (idPago, idPedido, idMetodoPago, idEstadoPago, montoPago, fechaPago, referenciaSimulada) VALUES
    (1, 1, 2, 2, 97900.00, '2026-01-01T09:01:00', N'SIM-000001'),
    (2, 2, 3, 2, 220900.00, '2026-01-08T10:14:00', N'SIM-000002'),
    (3, 3, 1, 2, 431900.00, '2026-01-15T11:27:00', N'SIM-000003'),
    (4, 4, 2, 2, 42300.00, '2026-02-04T13:53:00', N'SIM-000004'),
    (5, 5, 3, 2, 644500.00, '2026-02-11T14:06:00', N'SIM-000005'),
    (6, 6, 1, 2, 77020.00, '2026-02-22T12:40:00', N'SIM-000006'),
    (7, 7, 2, 2, 796520.00, '2026-03-07T17:45:00', N'SIM-000007'),
    (8, 8, 3, 4, 100000.00, '2026-03-14T10:16:00', N'SIM-000008'),
    (9, 9, 1, 2, 546700.00, '2026-03-18T15:19:00', N'SIM-000009'),
    (10, 10, 2, 2, 42100.00, '2026-03-25T16:32:00', N'SIM-000010'),
    (11, 11, 3, 2, 220200.00, '2026-04-03T11:24:00', N'SIM-000011'),
    (12, 12, 1, 2, 744700.00, '2026-04-14T09:58:00', N'SIM-000012'),
    (13, 13, 2, 2, 659000.00, '2026-04-21T10:11:00', N'SIM-000013'),
    (14, 14, 3, 2, 233900.00, '2026-05-10T12:37:00', N'SIM-000014'),
    (15, 15, 1, 2, 292400.00, '2026-05-17T13:50:00', N'SIM-000015'),
    (16, 16, 2, 2, 632900.00, '2026-05-24T14:03:00', N'SIM-000016'),
    (17, 17, 3, 2, 277900.00, '2026-06-06T15:16:00', N'SIM-000017'),
    (18, 18, 1, 2, 43300.00, '2026-06-13T16:29:00', N'SIM-000018'),
    (19, 19, 2, 2, 32700.00, '2026-06-20T17:42:00', N'SIM-000019'),
    (20, 20, 3, 2, 304800.00, '2026-07-02T09:55:00', N'SIM-000020'),
    (21, 21, 1, 2, 343200.00, '2026-07-09T10:08:00', N'SIM-000021'),
    (22, 22, 2, 4, 151000.00, '2026-07-09T16:31:00', N'SIM-000022'),
    (23, 23, 3, 2, 407200.00, '2026-07-16T11:21:00', N'SIM-000023'),
    (24, 24, 1, 2, 274200.00, '2026-08-05T13:47:00', N'SIM-000024'),
    (25, 25, 2, 2, 420300.00, '2026-08-12T15:00:00', N'SIM-000025'),
    (26, 26, 3, 2, 359900.00, '2026-08-23T12:34:00', N'SIM-000026'),
    (27, 27, 1, 2, 272700.00, '2026-09-01T16:26:00', N'SIM-000027'),
    (28, 28, 2, 2, 38700.00, '2026-09-08T17:39:00', N'SIM-000028'),
    (29, 29, 3, 2, 203700.00, '2026-09-19T15:13:00', N'SIM-000029'),
    (30, 30, 1, 2, 166400.00, '2026-10-04T11:18:00', N'SIM-000030'),
    (31, 31, 2, 2, 520700.00, '2026-10-15T09:52:00', N'SIM-000031'),
    (32, 32, 3, 2, 719800.00, '2026-10-22T10:05:00', N'SIM-000032'),
    (33, 33, 1, 2, 272396.00, '2026-11-03T15:21:00', N'SIM-000033'),
    (34, 34, 2, 4, 254000.00, '2026-11-18T12:46:00', N'SIM-000034'),
    (35, 35, 3, 2, 372350.00, '2026-11-21T10:06:00', N'SIM-000035'),
    (36, 36, 1, 2, 291000.00, '2026-11-23T18:41:00', N'SIM-000036'),
    (37, 37, 2, 2, 429300.00, '2026-11-25T11:11:00', N'SIM-000037');
SET IDENTITY_INSERT PAGO OFF;

-- Envío 1 = Pendiente, 2 = En tránsito, 3 = Entregado
SET IDENTITY_INSERT ENVIO ON;
INSERT INTO ENVIO (idEnvio, idPedido, empresaTransporte, codigoSeguimiento, fechaEnvio, fechaEntrega, idEstadoEnvio) VALUES
    (1, 1, N'RutaExpress', N'TRK20260001', '2026-01-03T09:00:00', '2026-01-05T09:00:00', 3),
    (2, 2, N'RutaExpress', N'TRK20260002', '2026-01-10T10:13:00', '2026-01-12T10:13:00', 3),
    (3, 3, N'RutaExpress', N'TRK20260003', '2026-01-17T11:26:00', '2026-01-19T11:26:00', 3),
    (4, 4, N'RutaExpress', N'TRK20260004', '2026-02-06T13:52:00', '2026-02-08T13:52:00', 3),
    (5, 5, N'RutaExpress', N'TRK20260005', '2026-02-13T14:05:00', '2026-02-15T14:05:00', 3),
    (6, 6, N'RutaExpress', N'TRK20260006', '2026-02-24T12:39:00', '2026-02-26T12:39:00', 3),
    (7, 7, N'RutaExpress', N'TRK20260007', '2026-03-09T17:44:00', '2026-03-11T17:44:00', 3),
    (8, 8, NULL, NULL, NULL, NULL, 1),
    (9, 9, N'RutaExpress', N'TRK20260009', '2026-03-20T15:18:00', '2026-03-22T15:18:00', 3),
    (10, 10, N'RutaExpress', N'TRK20260010', '2026-03-27T16:31:00', '2026-03-29T16:31:00', 3),
    (11, 11, N'RutaExpress', N'TRK20260011', '2026-04-05T11:23:00', '2026-04-07T11:23:00', 3),
    (12, 12, N'RutaExpress', N'TRK20260012', '2026-04-16T09:57:00', '2026-04-18T09:57:00', 3),
    (13, 13, N'RutaExpress', N'TRK20260013', '2026-04-23T10:10:00', '2026-04-25T10:10:00', 3),
    (14, 14, N'RutaExpress', N'TRK20260014', '2026-05-12T12:36:00', '2026-05-14T12:36:00', 3),
    (15, 15, N'RutaExpress', N'TRK20260015', '2026-05-19T13:49:00', '2026-05-21T13:49:00', 3),
    (16, 16, N'RutaExpress', N'TRK20260016', '2026-05-26T14:02:00', '2026-05-28T14:02:00', 3),
    (17, 17, N'RutaExpress', N'TRK20260017', '2026-06-08T15:15:00', '2026-06-10T15:15:00', 3),
    (18, 18, N'RutaExpress', N'TRK20260018', '2026-06-15T16:28:00', '2026-06-17T16:28:00', 3),
    (19, 19, N'RutaExpress', N'TRK20260019', '2026-06-22T17:41:00', '2026-06-24T17:41:00', 3),
    (20, 20, N'RutaExpress', N'TRK20260020', '2026-07-04T09:54:00', '2026-07-06T09:54:00', 3),
    (21, 21, N'RutaExpress', N'TRK20260021', '2026-07-11T10:07:00', '2026-07-13T10:07:00', 3),
    (22, 22, NULL, NULL, NULL, NULL, 1),
    (23, 23, N'RutaExpress', N'TRK20260023', '2026-07-18T11:20:00', '2026-07-20T11:20:00', 3),
    (24, 24, N'RutaExpress', N'TRK20260024', '2026-08-07T13:46:00', '2026-08-09T13:46:00', 3),
    (25, 25, N'RutaExpress', N'TRK20260025', '2026-08-14T14:59:00', '2026-08-16T14:59:00', 3),
    (26, 26, N'RutaExpress', N'TRK20260026', '2026-08-25T12:33:00', '2026-08-27T12:33:00', 3),
    (27, 27, N'RutaExpress', N'TRK20260027', '2026-09-03T16:25:00', '2026-09-05T16:25:00', 3),
    (28, 28, N'RutaExpress', N'TRK20260028', '2026-09-10T17:38:00', '2026-09-12T17:38:00', 3),
    (29, 29, N'RutaExpress', N'TRK20260029', '2026-09-21T15:12:00', '2026-09-23T15:12:00', 3),
    (30, 30, N'RutaExpress', N'TRK20260030', '2026-10-06T11:17:00', '2026-10-08T11:17:00', 3),
    (31, 31, N'RutaExpress', N'TRK20260031', '2026-10-17T09:51:00', '2026-10-19T09:51:00', 3),
    (32, 32, N'RutaExpress', N'TRK20260032', '2026-10-24T10:04:00', '2026-10-26T10:04:00', 3),
    (33, 33, N'RutaExpress', N'TRK20260033', '2026-11-05T15:20:00', '2026-11-07T15:20:00', 3),
    (34, 34, NULL, NULL, NULL, NULL, 1),
    (35, 35, N'RutaExpress', N'TRK20260035', '2026-11-23T10:05:00', NULL, 2),
    (36, 36, NULL, NULL, NULL, NULL, 1),
    (37, 37, NULL, NULL, NULL, NULL, 1);
SET IDENTITY_INSERT ENVIO OFF;

-- Una fila por cada estado por el que pasó el pedido
SET IDENTITY_INSERT HISTORIAL_ESTADO_PEDIDO ON;
INSERT INTO HISTORIAL_ESTADO_PEDIDO (idHistorial, idPedido, idEstadoPedido, fechaCambio, observacion) VALUES
    (1, 1, 1, '2026-01-01T09:00:00', N'Pedido creado'),
    (2, 1, 2, '2026-01-01T09:01:00', N'Pago aprobado'),
    (3, 1, 3, '2026-01-02T09:00:00', N'Pedido en bodega'),
    (4, 1, 4, '2026-01-03T09:00:00', N'Entregado a la transportista'),
    (5, 1, 5, '2026-01-05T09:00:00', N'Recibido por el cliente'),
    (6, 2, 1, '2026-01-08T10:13:00', N'Pedido creado'),
    (7, 2, 2, '2026-01-08T10:14:00', N'Pago aprobado'),
    (8, 2, 3, '2026-01-09T10:13:00', N'Pedido en bodega'),
    (9, 2, 4, '2026-01-10T10:13:00', N'Entregado a la transportista'),
    (10, 2, 5, '2026-01-12T10:13:00', N'Recibido por el cliente'),
    (11, 3, 1, '2026-01-15T11:26:00', N'Pedido creado'),
    (12, 3, 2, '2026-01-15T11:27:00', N'Pago aprobado'),
    (13, 3, 3, '2026-01-16T11:26:00', N'Pedido en bodega'),
    (14, 3, 4, '2026-01-17T11:26:00', N'Entregado a la transportista'),
    (15, 3, 5, '2026-01-19T11:26:00', N'Recibido por el cliente'),
    (16, 4, 1, '2026-02-04T13:52:00', N'Pedido creado'),
    (17, 4, 2, '2026-02-04T13:53:00', N'Pago aprobado'),
    (18, 4, 3, '2026-02-05T13:52:00', N'Pedido en bodega'),
    (19, 4, 4, '2026-02-06T13:52:00', N'Entregado a la transportista'),
    (20, 4, 5, '2026-02-08T13:52:00', N'Recibido por el cliente'),
    (21, 5, 1, '2026-02-11T14:05:00', N'Pedido creado'),
    (22, 5, 2, '2026-02-11T14:06:00', N'Pago aprobado'),
    (23, 5, 3, '2026-02-12T14:05:00', N'Pedido en bodega'),
    (24, 5, 4, '2026-02-13T14:05:00', N'Entregado a la transportista'),
    (25, 5, 5, '2026-02-15T14:05:00', N'Recibido por el cliente'),
    (26, 6, 1, '2026-02-22T12:39:00', N'Pedido creado'),
    (27, 6, 2, '2026-02-22T12:40:00', N'Pago aprobado'),
    (28, 6, 3, '2026-02-23T12:39:00', N'Pedido en bodega'),
    (29, 6, 4, '2026-02-24T12:39:00', N'Entregado a la transportista'),
    (30, 6, 5, '2026-02-26T12:39:00', N'Recibido por el cliente'),
    (31, 7, 1, '2026-03-07T17:44:00', N'Pedido creado'),
    (32, 7, 2, '2026-03-07T17:45:00', N'Pago aprobado'),
    (33, 7, 3, '2026-03-08T17:44:00', N'Pedido en bodega'),
    (34, 7, 4, '2026-03-09T17:44:00', N'Entregado a la transportista'),
    (35, 7, 5, '2026-03-11T17:44:00', N'Recibido por el cliente'),
    (36, 8, 1, '2026-03-14T10:15:00', N'Pedido creado'),
    (37, 8, 2, '2026-03-14T10:16:00', N'Pago aprobado'),
    (38, 8, 6, '2026-03-14T15:16:00', N'Cancelado por el cliente'),
    (39, 9, 1, '2026-03-18T15:18:00', N'Pedido creado'),
    (40, 9, 2, '2026-03-18T15:19:00', N'Pago aprobado'),
    (41, 9, 3, '2026-03-19T15:18:00', N'Pedido en bodega'),
    (42, 9, 4, '2026-03-20T15:18:00', N'Entregado a la transportista'),
    (43, 9, 5, '2026-03-22T15:18:00', N'Recibido por el cliente'),
    (44, 10, 1, '2026-03-25T16:31:00', N'Pedido creado'),
    (45, 10, 2, '2026-03-25T16:32:00', N'Pago aprobado'),
    (46, 10, 3, '2026-03-26T16:31:00', N'Pedido en bodega'),
    (47, 10, 4, '2026-03-27T16:31:00', N'Entregado a la transportista'),
    (48, 10, 5, '2026-03-29T16:31:00', N'Recibido por el cliente'),
    (49, 11, 1, '2026-04-03T11:23:00', N'Pedido creado'),
    (50, 11, 2, '2026-04-03T11:24:00', N'Pago aprobado'),
    (51, 11, 3, '2026-04-04T11:23:00', N'Pedido en bodega'),
    (52, 11, 4, '2026-04-05T11:23:00', N'Entregado a la transportista'),
    (53, 11, 5, '2026-04-07T11:23:00', N'Recibido por el cliente'),
    (54, 12, 1, '2026-04-14T09:57:00', N'Pedido creado'),
    (55, 12, 2, '2026-04-14T09:58:00', N'Pago aprobado'),
    (56, 12, 3, '2026-04-15T09:57:00', N'Pedido en bodega'),
    (57, 12, 4, '2026-04-16T09:57:00', N'Entregado a la transportista'),
    (58, 12, 5, '2026-04-18T09:57:00', N'Recibido por el cliente'),
    (59, 13, 1, '2026-04-21T10:10:00', N'Pedido creado'),
    (60, 13, 2, '2026-04-21T10:11:00', N'Pago aprobado'),
    (61, 13, 3, '2026-04-22T10:10:00', N'Pedido en bodega'),
    (62, 13, 4, '2026-04-23T10:10:00', N'Entregado a la transportista'),
    (63, 13, 5, '2026-04-25T10:10:00', N'Recibido por el cliente'),
    (64, 14, 1, '2026-05-10T12:36:00', N'Pedido creado'),
    (65, 14, 2, '2026-05-10T12:37:00', N'Pago aprobado'),
    (66, 14, 3, '2026-05-11T12:36:00', N'Pedido en bodega'),
    (67, 14, 4, '2026-05-12T12:36:00', N'Entregado a la transportista'),
    (68, 14, 5, '2026-05-14T12:36:00', N'Recibido por el cliente'),
    (69, 15, 1, '2026-05-17T13:49:00', N'Pedido creado'),
    (70, 15, 2, '2026-05-17T13:50:00', N'Pago aprobado'),
    (71, 15, 3, '2026-05-18T13:49:00', N'Pedido en bodega'),
    (72, 15, 4, '2026-05-19T13:49:00', N'Entregado a la transportista'),
    (73, 15, 5, '2026-05-21T13:49:00', N'Recibido por el cliente'),
    (74, 16, 1, '2026-05-24T14:02:00', N'Pedido creado'),
    (75, 16, 2, '2026-05-24T14:03:00', N'Pago aprobado'),
    (76, 16, 3, '2026-05-25T14:02:00', N'Pedido en bodega'),
    (77, 16, 4, '2026-05-26T14:02:00', N'Entregado a la transportista'),
    (78, 16, 5, '2026-05-28T14:02:00', N'Recibido por el cliente'),
    (79, 17, 1, '2026-06-06T15:15:00', N'Pedido creado'),
    (80, 17, 2, '2026-06-06T15:16:00', N'Pago aprobado'),
    (81, 17, 3, '2026-06-07T15:15:00', N'Pedido en bodega'),
    (82, 17, 4, '2026-06-08T15:15:00', N'Entregado a la transportista'),
    (83, 17, 5, '2026-06-10T15:15:00', N'Recibido por el cliente'),
    (84, 18, 1, '2026-06-13T16:28:00', N'Pedido creado'),
    (85, 18, 2, '2026-06-13T16:29:00', N'Pago aprobado'),
    (86, 18, 3, '2026-06-14T16:28:00', N'Pedido en bodega'),
    (87, 18, 4, '2026-06-15T16:28:00', N'Entregado a la transportista'),
    (88, 18, 5, '2026-06-17T16:28:00', N'Recibido por el cliente'),
    (89, 19, 1, '2026-06-20T17:41:00', N'Pedido creado'),
    (90, 19, 2, '2026-06-20T17:42:00', N'Pago aprobado'),
    (91, 19, 3, '2026-06-21T17:41:00', N'Pedido en bodega'),
    (92, 19, 4, '2026-06-22T17:41:00', N'Entregado a la transportista'),
    (93, 19, 5, '2026-06-24T17:41:00', N'Recibido por el cliente'),
    (94, 20, 1, '2026-07-02T09:54:00', N'Pedido creado'),
    (95, 20, 2, '2026-07-02T09:55:00', N'Pago aprobado'),
    (96, 20, 3, '2026-07-03T09:54:00', N'Pedido en bodega'),
    (97, 20, 4, '2026-07-04T09:54:00', N'Entregado a la transportista'),
    (98, 20, 5, '2026-07-06T09:54:00', N'Recibido por el cliente'),
    (99, 21, 1, '2026-07-09T10:07:00', N'Pedido creado'),
    (100, 21, 2, '2026-07-09T10:08:00', N'Pago aprobado'),
    (101, 21, 3, '2026-07-10T10:07:00', N'Pedido en bodega'),
    (102, 21, 4, '2026-07-11T10:07:00', N'Entregado a la transportista'),
    (103, 21, 5, '2026-07-13T10:07:00', N'Recibido por el cliente'),
    (104, 22, 1, '2026-07-09T16:30:00', N'Pedido creado'),
    (105, 22, 2, '2026-07-09T16:31:00', N'Pago aprobado'),
    (106, 22, 3, '2026-07-10T16:30:00', N'Pedido en bodega'),
    (107, 22, 6, '2026-07-10T21:30:00', N'Cancelado por el cliente'),
    (108, 23, 1, '2026-07-16T11:20:00', N'Pedido creado'),
    (109, 23, 2, '2026-07-16T11:21:00', N'Pago aprobado'),
    (110, 23, 3, '2026-07-17T11:20:00', N'Pedido en bodega'),
    (111, 23, 4, '2026-07-18T11:20:00', N'Entregado a la transportista'),
    (112, 23, 5, '2026-07-20T11:20:00', N'Recibido por el cliente'),
    (113, 24, 1, '2026-08-05T13:46:00', N'Pedido creado'),
    (114, 24, 2, '2026-08-05T13:47:00', N'Pago aprobado'),
    (115, 24, 3, '2026-08-06T13:46:00', N'Pedido en bodega'),
    (116, 24, 4, '2026-08-07T13:46:00', N'Entregado a la transportista'),
    (117, 24, 5, '2026-08-09T13:46:00', N'Recibido por el cliente'),
    (118, 25, 1, '2026-08-12T14:59:00', N'Pedido creado'),
    (119, 25, 2, '2026-08-12T15:00:00', N'Pago aprobado'),
    (120, 25, 3, '2026-08-13T14:59:00', N'Pedido en bodega'),
    (121, 25, 4, '2026-08-14T14:59:00', N'Entregado a la transportista'),
    (122, 25, 5, '2026-08-16T14:59:00', N'Recibido por el cliente'),
    (123, 26, 1, '2026-08-23T12:33:00', N'Pedido creado'),
    (124, 26, 2, '2026-08-23T12:34:00', N'Pago aprobado'),
    (125, 26, 3, '2026-08-24T12:33:00', N'Pedido en bodega'),
    (126, 26, 4, '2026-08-25T12:33:00', N'Entregado a la transportista'),
    (127, 26, 5, '2026-08-27T12:33:00', N'Recibido por el cliente'),
    (128, 27, 1, '2026-09-01T16:25:00', N'Pedido creado'),
    (129, 27, 2, '2026-09-01T16:26:00', N'Pago aprobado'),
    (130, 27, 3, '2026-09-02T16:25:00', N'Pedido en bodega'),
    (131, 27, 4, '2026-09-03T16:25:00', N'Entregado a la transportista'),
    (132, 27, 5, '2026-09-05T16:25:00', N'Recibido por el cliente'),
    (133, 28, 1, '2026-09-08T17:38:00', N'Pedido creado'),
    (134, 28, 2, '2026-09-08T17:39:00', N'Pago aprobado'),
    (135, 28, 3, '2026-09-09T17:38:00', N'Pedido en bodega'),
    (136, 28, 4, '2026-09-10T17:38:00', N'Entregado a la transportista'),
    (137, 28, 5, '2026-09-12T17:38:00', N'Recibido por el cliente'),
    (138, 29, 1, '2026-09-19T15:12:00', N'Pedido creado'),
    (139, 29, 2, '2026-09-19T15:13:00', N'Pago aprobado'),
    (140, 29, 3, '2026-09-20T15:12:00', N'Pedido en bodega'),
    (141, 29, 4, '2026-09-21T15:12:00', N'Entregado a la transportista'),
    (142, 29, 5, '2026-09-23T15:12:00', N'Recibido por el cliente'),
    (143, 30, 1, '2026-10-04T11:17:00', N'Pedido creado'),
    (144, 30, 2, '2026-10-04T11:18:00', N'Pago aprobado'),
    (145, 30, 3, '2026-10-05T11:17:00', N'Pedido en bodega'),
    (146, 30, 4, '2026-10-06T11:17:00', N'Entregado a la transportista'),
    (147, 30, 5, '2026-10-08T11:17:00', N'Recibido por el cliente'),
    (148, 31, 1, '2026-10-15T09:51:00', N'Pedido creado'),
    (149, 31, 2, '2026-10-15T09:52:00', N'Pago aprobado'),
    (150, 31, 3, '2026-10-16T09:51:00', N'Pedido en bodega'),
    (151, 31, 4, '2026-10-17T09:51:00', N'Entregado a la transportista'),
    (152, 31, 5, '2026-10-19T09:51:00', N'Recibido por el cliente'),
    (153, 32, 1, '2026-10-22T10:04:00', N'Pedido creado'),
    (154, 32, 2, '2026-10-22T10:05:00', N'Pago aprobado'),
    (155, 32, 3, '2026-10-23T10:04:00', N'Pedido en bodega'),
    (156, 32, 4, '2026-10-24T10:04:00', N'Entregado a la transportista'),
    (157, 32, 5, '2026-10-26T10:04:00', N'Recibido por el cliente'),
    (158, 33, 1, '2026-11-03T15:20:00', N'Pedido creado'),
    (159, 33, 2, '2026-11-03T15:21:00', N'Pago aprobado'),
    (160, 33, 3, '2026-11-04T15:20:00', N'Pedido en bodega'),
    (161, 33, 4, '2026-11-05T15:20:00', N'Entregado a la transportista'),
    (162, 33, 5, '2026-11-07T15:20:00', N'Recibido por el cliente'),
    (163, 34, 1, '2026-11-18T12:45:00', N'Pedido creado'),
    (164, 34, 2, '2026-11-18T12:46:00', N'Pago aprobado'),
    (165, 34, 6, '2026-11-18T17:46:00', N'Cancelado por el cliente'),
    (166, 35, 1, '2026-11-21T10:05:00', N'Pedido creado'),
    (167, 35, 2, '2026-11-21T10:06:00', N'Pago aprobado'),
    (168, 35, 3, '2026-11-22T10:05:00', N'Pedido en bodega'),
    (169, 35, 4, '2026-11-23T10:05:00', N'Entregado a la transportista'),
    (170, 36, 1, '2026-11-23T18:40:00', N'Pedido creado'),
    (171, 36, 2, '2026-11-23T18:41:00', N'Pago aprobado'),
    (172, 36, 3, '2026-11-24T18:40:00', N'Pedido en bodega'),
    (173, 37, 1, '2026-11-25T11:10:00', N'Pedido creado'),
    (174, 37, 2, '2026-11-25T11:11:00', N'Pago aprobado');
SET IDENTITY_INSERT HISTORIAL_ESTADO_PEDIDO OFF;

-- ======================== 8. MOVIMIENTOS DE INVENTARIO ========================

-- ENTRADA inicial y reabastecimiento (admin), SALIDA por línea vendida
-- (usuario del cliente), DEVOLUCION por línea de pedido cancelado (admin)
SET IDENTITY_INSERT MOVIMIENTO_INVENTARIO ON;
INSERT INTO MOVIMIENTO_INVENTARIO (idMovimiento, idInventario, idUsuario, idPedido, tipoMovimiento, cantidad, fechaMovimiento, motivo) VALUES
    (1, 1, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (2, 2, 1, NULL, N'ENTRADA', 20, '2025-12-30T08:00:00', N'Inventario inicial'),
    (3, 3, 1, NULL, N'ENTRADA', 20, '2025-12-30T08:00:00', N'Inventario inicial'),
    (4, 4, 1, NULL, N'ENTRADA', 20, '2025-12-30T08:00:00', N'Inventario inicial'),
    (5, 5, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (6, 6, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (7, 7, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (8, 8, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (9, 9, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (10, 10, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (11, 11, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (12, 12, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (13, 13, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (14, 14, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (15, 15, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (16, 16, 1, NULL, N'ENTRADA', 20, '2025-12-30T08:00:00', N'Inventario inicial'),
    (17, 17, 1, NULL, N'ENTRADA', 20, '2025-12-30T08:00:00', N'Inventario inicial'),
    (18, 18, 1, NULL, N'ENTRADA', 20, '2025-12-30T08:00:00', N'Inventario inicial'),
    (19, 19, 1, NULL, N'ENTRADA', 20, '2025-12-30T08:00:00', N'Inventario inicial'),
    (20, 20, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (21, 21, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (22, 22, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (23, 23, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (24, 24, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (25, 25, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (26, 26, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (27, 27, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (28, 28, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (29, 29, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (30, 30, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (31, 31, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (32, 32, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (33, 33, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (34, 34, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (35, 35, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (36, 36, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (37, 37, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (38, 38, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (39, 39, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (40, 40, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (41, 41, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (42, 42, 1, NULL, N'ENTRADA', 20, '2025-12-30T08:00:00', N'Inventario inicial'),
    (43, 43, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (44, 44, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (45, 45, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (46, 46, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (47, 47, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (48, 48, 1, NULL, N'ENTRADA', 40, '2025-12-30T08:00:00', N'Inventario inicial'),
    (49, 49, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (50, 50, 1, NULL, N'ENTRADA', 60, '2025-12-30T08:00:00', N'Inventario inicial'),
    (51, 4, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (52, 8, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (53, 12, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (54, 16, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (55, 20, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (56, 24, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (57, 28, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (58, 32, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (59, 36, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (60, 40, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (61, 44, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (62, 48, 1, NULL, N'ENTRADA', 20, '2026-07-01T08:00:00', N'Reabastecimiento de mitad de año'),
    (63, 21, 2, 1, N'SALIDA', 3, '2026-01-01T09:01:00', N'Venta pedido #1'),
    (64, 33, 2, 1, N'SALIDA', 3, '2026-01-01T09:01:00', N'Venta pedido #1'),
    (65, 15, 3, 2, N'SALIDA', 3, '2026-01-08T10:14:00', N'Venta pedido #2'),
    (66, 39, 3, 2, N'SALIDA', 3, '2026-01-08T10:14:00', N'Venta pedido #2'),
    (67, 37, 4, 3, N'SALIDA', 1, '2026-01-15T11:27:00', N'Venta pedido #3'),
    (68, 36, 4, 3, N'SALIDA', 3, '2026-01-15T11:27:00', N'Venta pedido #3'),
    (69, 47, 4, 3, N'SALIDA', 1, '2026-01-15T11:27:00', N'Venta pedido #3'),
    (70, 32, 4, 3, N'SALIDA', 1, '2026-01-15T11:27:00', N'Venta pedido #3'),
    (71, 38, 4, 3, N'SALIDA', 2, '2026-01-15T11:27:00', N'Venta pedido #3'),
    (72, 29, 4, 3, N'SALIDA', 1, '2026-01-15T11:27:00', N'Venta pedido #3'),
    (73, 16, 4, 3, N'SALIDA', 2, '2026-01-15T11:27:00', N'Venta pedido #3'),
    (74, 44, 6, 4, N'SALIDA', 2, '2026-02-04T13:53:00', N'Venta pedido #4'),
    (75, 14, 7, 5, N'SALIDA', 3, '2026-02-11T14:06:00', N'Venta pedido #5'),
    (76, 26, 7, 5, N'SALIDA', 3, '2026-02-11T14:06:00', N'Venta pedido #5'),
    (77, 17, 7, 5, N'SALIDA', 3, '2026-02-11T14:06:00', N'Venta pedido #5'),
    (78, 23, 7, 5, N'SALIDA', 1, '2026-02-11T14:06:00', N'Venta pedido #5'),
    (79, 47, 7, 5, N'SALIDA', 3, '2026-02-11T14:06:00', N'Venta pedido #5'),
    (80, 25, 7, 5, N'SALIDA', 2, '2026-02-11T14:06:00', N'Venta pedido #5'),
    (81, 36, 5, 6, N'SALIDA', 2, '2026-02-22T12:40:00', N'Venta pedido #6'),
    (82, 35, 5, 6, N'SALIDA', 2, '2026-02-22T12:40:00', N'Venta pedido #6'),
    (83, 10, 10, 7, N'SALIDA', 2, '2026-03-07T17:45:00', N'Venta pedido #7'),
    (84, 42, 10, 7, N'SALIDA', 2, '2026-03-07T17:45:00', N'Venta pedido #7'),
    (85, 46, 10, 7, N'SALIDA', 2, '2026-03-07T17:45:00', N'Venta pedido #7'),
    (86, 48, 10, 7, N'SALIDA', 1, '2026-03-07T17:45:00', N'Venta pedido #7'),
    (87, 37, 10, 7, N'SALIDA', 2, '2026-03-07T17:45:00', N'Venta pedido #7'),
    (88, 20, 10, 7, N'SALIDA', 3, '2026-03-07T17:45:00', N'Venta pedido #7'),
    (89, 2, 10, 7, N'SALIDA', 3, '2026-03-07T17:45:00', N'Venta pedido #7'),
    (90, 24, 10, 7, N'SALIDA', 2, '2026-03-07T17:45:00', N'Venta pedido #7'),
    (91, 28, 2, 8, N'SALIDA', 3, '2026-03-14T10:16:00', N'Venta pedido #8'),
    (92, 33, 2, 8, N'SALIDA', 2, '2026-03-14T10:16:00', N'Venta pedido #8'),
    (93, 28, 1, 8, N'DEVOLUCION', 3, '2026-03-14T15:16:00', N'Cancelación pedido #8'),
    (94, 33, 1, 8, N'DEVOLUCION', 2, '2026-03-14T15:16:00', N'Cancelación pedido #8'),
    (95, 34, 8, 9, N'SALIDA', 1, '2026-03-18T15:19:00', N'Venta pedido #9'),
    (96, 17, 8, 9, N'SALIDA', 3, '2026-03-18T15:19:00', N'Venta pedido #9'),
    (97, 27, 8, 9, N'SALIDA', 1, '2026-03-18T15:19:00', N'Venta pedido #9'),
    (98, 37, 8, 9, N'SALIDA', 1, '2026-03-18T15:19:00', N'Venta pedido #9'),
    (99, 31, 8, 9, N'SALIDA', 1, '2026-03-18T15:19:00', N'Venta pedido #9'),
    (100, 33, 8, 9, N'SALIDA', 3, '2026-03-18T15:19:00', N'Venta pedido #9'),
    (101, 50, 8, 9, N'SALIDA', 3, '2026-03-18T15:19:00', N'Venta pedido #9'),
    (102, 46, 9, 10, N'SALIDA', 2, '2026-03-25T16:32:00', N'Venta pedido #10'),
    (103, 40, 9, 10, N'SALIDA', 2, '2026-03-25T16:32:00', N'Venta pedido #10'),
    (104, 31, 13, 11, N'SALIDA', 3, '2026-04-03T11:24:00', N'Venta pedido #11'),
    (105, 15, 13, 11, N'SALIDA', 3, '2026-04-03T11:24:00', N'Venta pedido #11'),
    (106, 8, 13, 11, N'SALIDA', 2, '2026-04-03T11:24:00', N'Venta pedido #11'),
    (107, 46, 11, 12, N'SALIDA', 3, '2026-04-14T09:58:00', N'Venta pedido #12'),
    (108, 35, 11, 12, N'SALIDA', 3, '2026-04-14T09:58:00', N'Venta pedido #12'),
    (109, 17, 11, 12, N'SALIDA', 3, '2026-04-14T09:58:00', N'Venta pedido #12'),
    (110, 36, 11, 12, N'SALIDA', 2, '2026-04-14T09:58:00', N'Venta pedido #12'),
    (111, 26, 11, 12, N'SALIDA', 2, '2026-04-14T09:58:00', N'Venta pedido #12'),
    (112, 43, 11, 12, N'SALIDA', 2, '2026-04-14T09:58:00', N'Venta pedido #12'),
    (113, 20, 11, 12, N'SALIDA', 1, '2026-04-14T09:58:00', N'Venta pedido #12'),
    (114, 47, 11, 12, N'SALIDA', 2, '2026-04-14T09:58:00', N'Venta pedido #12'),
    (115, 1, 12, 13, N'SALIDA', 2, '2026-04-21T10:11:00', N'Venta pedido #13'),
    (116, 3, 12, 13, N'SALIDA', 3, '2026-04-21T10:11:00', N'Venta pedido #13'),
    (117, 10, 12, 13, N'SALIDA', 2, '2026-04-21T10:11:00', N'Venta pedido #13'),
    (118, 42, 12, 13, N'SALIDA', 2, '2026-04-21T10:11:00', N'Venta pedido #13'),
    (119, 39, 12, 13, N'SALIDA', 1, '2026-04-21T10:11:00', N'Venta pedido #13'),
    (120, 45, 14, 14, N'SALIDA', 2, '2026-05-10T12:37:00', N'Venta pedido #14'),
    (121, 32, 14, 14, N'SALIDA', 2, '2026-05-10T12:37:00', N'Venta pedido #14'),
    (122, 30, 14, 14, N'SALIDA', 3, '2026-05-10T12:37:00', N'Venta pedido #14'),
    (123, 33, 14, 14, N'SALIDA', 3, '2026-05-10T12:37:00', N'Venta pedido #14'),
    (124, 50, 14, 14, N'SALIDA', 1, '2026-05-10T12:37:00', N'Venta pedido #14'),
    (125, 21, 15, 15, N'SALIDA', 3, '2026-05-17T13:50:00', N'Venta pedido #15'),
    (126, 30, 15, 15, N'SALIDA', 3, '2026-05-17T13:50:00', N'Venta pedido #15'),
    (127, 7, 15, 15, N'SALIDA', 2, '2026-05-17T13:50:00', N'Venta pedido #15'),
    (128, 29, 15, 15, N'SALIDA', 2, '2026-05-17T13:50:00', N'Venta pedido #15'),
    (129, 45, 15, 15, N'SALIDA', 1, '2026-05-17T13:50:00', N'Venta pedido #15'),
    (130, 47, 16, 16, N'SALIDA', 1, '2026-05-24T14:03:00', N'Venta pedido #16'),
    (131, 31, 16, 16, N'SALIDA', 1, '2026-05-24T14:03:00', N'Venta pedido #16'),
    (132, 5, 16, 16, N'SALIDA', 3, '2026-05-24T14:03:00', N'Venta pedido #16'),
    (133, 42, 16, 16, N'SALIDA', 2, '2026-05-24T14:03:00', N'Venta pedido #16'),
    (134, 18, 16, 16, N'SALIDA', 1, '2026-05-24T14:03:00', N'Venta pedido #16'),
    (135, 32, 16, 16, N'SALIDA', 2, '2026-05-24T14:03:00', N'Venta pedido #16'),
    (136, 24, 16, 16, N'SALIDA', 1, '2026-05-24T14:03:00', N'Venta pedido #16'),
    (137, 1, 2, 17, N'SALIDA', 3, '2026-06-06T15:16:00', N'Venta pedido #17'),
    (138, 29, 2, 17, N'SALIDA', 3, '2026-06-06T15:16:00', N'Venta pedido #17'),
    (139, 40, 3, 18, N'SALIDA', 1, '2026-06-13T16:29:00', N'Venta pedido #18'),
    (140, 13, 3, 18, N'SALIDA', 1, '2026-06-13T16:29:00', N'Venta pedido #18'),
    (141, 49, 4, 19, N'SALIDA', 3, '2026-06-20T17:42:00', N'Venta pedido #19'),
    (142, 43, 5, 20, N'SALIDA', 1, '2026-07-02T09:55:00', N'Venta pedido #20'),
    (143, 49, 5, 20, N'SALIDA', 2, '2026-07-02T09:55:00', N'Venta pedido #20'),
    (144, 41, 5, 20, N'SALIDA', 3, '2026-07-02T09:55:00', N'Venta pedido #20'),
    (145, 23, 5, 20, N'SALIDA', 3, '2026-07-02T09:55:00', N'Venta pedido #20'),
    (146, 10, 5, 20, N'SALIDA', 3, '2026-07-02T09:55:00', N'Venta pedido #20'),
    (147, 45, 6, 21, N'SALIDA', 3, '2026-07-09T10:08:00', N'Venta pedido #21'),
    (148, 47, 6, 21, N'SALIDA', 3, '2026-07-09T10:08:00', N'Venta pedido #21'),
    (149, 9, 6, 21, N'SALIDA', 3, '2026-07-09T10:08:00', N'Venta pedido #21'),
    (150, 35, 6, 21, N'SALIDA', 2, '2026-07-09T10:08:00', N'Venta pedido #21'),
    (151, 15, 6, 21, N'SALIDA', 1, '2026-07-09T10:08:00', N'Venta pedido #21'),
    (152, 31, 6, 21, N'SALIDA', 2, '2026-07-09T10:08:00', N'Venta pedido #21'),
    (153, 38, 6, 21, N'SALIDA', 3, '2026-07-09T10:08:00', N'Venta pedido #21'),
    (154, 48, 6, 21, N'SALIDA', 1, '2026-07-09T10:08:00', N'Venta pedido #21'),
    (155, 38, 3, 22, N'SALIDA', 2, '2026-07-09T16:31:00', N'Venta pedido #22'),
    (156, 20, 3, 22, N'SALIDA', 2, '2026-07-09T16:31:00', N'Venta pedido #22'),
    (157, 33, 3, 22, N'SALIDA', 1, '2026-07-09T16:31:00', N'Venta pedido #22'),
    (158, 38, 1, 22, N'DEVOLUCION', 2, '2026-07-10T21:30:00', N'Cancelación pedido #22'),
    (159, 20, 1, 22, N'DEVOLUCION', 2, '2026-07-10T21:30:00', N'Cancelación pedido #22'),
    (160, 33, 1, 22, N'DEVOLUCION', 1, '2026-07-10T21:30:00', N'Cancelación pedido #22'),
    (161, 25, 7, 23, N'SALIDA', 1, '2026-07-16T11:21:00', N'Venta pedido #23'),
    (162, 1, 7, 23, N'SALIDA', 2, '2026-07-16T11:21:00', N'Venta pedido #23'),
    (163, 7, 7, 23, N'SALIDA', 3, '2026-07-16T11:21:00', N'Venta pedido #23'),
    (164, 5, 7, 23, N'SALIDA', 2, '2026-07-16T11:21:00', N'Venta pedido #23'),
    (165, 2, 9, 24, N'SALIDA', 3, '2026-08-05T13:47:00', N'Venta pedido #24'),
    (166, 21, 10, 25, N'SALIDA', 3, '2026-08-12T15:00:00', N'Venta pedido #25'),
    (167, 44, 10, 25, N'SALIDA', 3, '2026-08-12T15:00:00', N'Venta pedido #25'),
    (168, 20, 10, 25, N'SALIDA', 1, '2026-08-12T15:00:00', N'Venta pedido #25'),
    (169, 29, 10, 25, N'SALIDA', 1, '2026-08-12T15:00:00', N'Venta pedido #25'),
    (170, 50, 10, 25, N'SALIDA', 3, '2026-08-12T15:00:00', N'Venta pedido #25'),
    (171, 8, 10, 25, N'SALIDA', 3, '2026-08-12T15:00:00', N'Venta pedido #25'),
    (172, 32, 10, 25, N'SALIDA', 1, '2026-08-12T15:00:00', N'Venta pedido #25'),
    (173, 30, 10, 25, N'SALIDA', 2, '2026-08-12T15:00:00', N'Venta pedido #25'),
    (174, 30, 8, 26, N'SALIDA', 3, '2026-08-23T12:34:00', N'Venta pedido #26'),
    (175, 39, 8, 26, N'SALIDA', 2, '2026-08-23T12:34:00', N'Venta pedido #26'),
    (176, 15, 8, 26, N'SALIDA', 1, '2026-08-23T12:34:00', N'Venta pedido #26'),
    (177, 44, 8, 26, N'SALIDA', 1, '2026-08-23T12:34:00', N'Venta pedido #26'),
    (178, 46, 8, 26, N'SALIDA', 3, '2026-08-23T12:34:00', N'Venta pedido #26'),
    (179, 5, 8, 26, N'SALIDA', 1, '2026-08-23T12:34:00', N'Venta pedido #26'),
    (180, 42, 12, 27, N'SALIDA', 3, '2026-09-01T16:26:00', N'Venta pedido #27'),
    (181, 29, 13, 28, N'SALIDA', 3, '2026-09-08T17:39:00', N'Venta pedido #28'),
    (182, 31, 11, 29, N'SALIDA', 1, '2026-09-19T15:13:00', N'Venta pedido #29'),
    (183, 46, 11, 29, N'SALIDA', 3, '2026-09-19T15:13:00', N'Venta pedido #29'),
    (184, 44, 11, 29, N'SALIDA', 3, '2026-09-19T15:13:00', N'Venta pedido #29'),
    (185, 2, 11, 29, N'SALIDA', 1, '2026-09-19T15:13:00', N'Venta pedido #29'),
    (186, 11, 16, 30, N'SALIDA', 2, '2026-10-04T11:18:00', N'Venta pedido #30'),
    (187, 43, 16, 30, N'SALIDA', 2, '2026-10-04T11:18:00', N'Venta pedido #30'),
    (188, 12, 16, 30, N'SALIDA', 2, '2026-10-04T11:18:00', N'Venta pedido #30'),
    (189, 6, 14, 31, N'SALIDA', 2, '2026-10-15T09:52:00', N'Venta pedido #31'),
    (190, 25, 14, 31, N'SALIDA', 2, '2026-10-15T09:52:00', N'Venta pedido #31'),
    (191, 20, 14, 31, N'SALIDA', 2, '2026-10-15T09:52:00', N'Venta pedido #31'),
    (192, 12, 14, 31, N'SALIDA', 2, '2026-10-15T09:52:00', N'Venta pedido #31'),
    (193, 23, 14, 31, N'SALIDA', 2, '2026-10-15T09:52:00', N'Venta pedido #31'),
    (194, 47, 14, 31, N'SALIDA', 1, '2026-10-15T09:52:00', N'Venta pedido #31'),
    (195, 17, 14, 31, N'SALIDA', 2, '2026-10-15T09:52:00', N'Venta pedido #31'),
    (196, 29, 15, 32, N'SALIDA', 1, '2026-10-22T10:05:00', N'Venta pedido #32'),
    (197, 8, 15, 32, N'SALIDA', 1, '2026-10-22T10:05:00', N'Venta pedido #32'),
    (198, 34, 15, 32, N'SALIDA', 2, '2026-10-22T10:05:00', N'Venta pedido #32'),
    (199, 48, 15, 32, N'SALIDA', 3, '2026-10-22T10:05:00', N'Venta pedido #32'),
    (200, 18, 15, 32, N'SALIDA', 2, '2026-10-22T10:05:00', N'Venta pedido #32'),
    (201, 7, 15, 32, N'SALIDA', 2, '2026-10-22T10:05:00', N'Venta pedido #32'),
    (202, 14, 15, 32, N'SALIDA', 3, '2026-10-22T10:05:00', N'Venta pedido #32'),
    (203, 15, 15, 32, N'SALIDA', 3, '2026-10-22T10:05:00', N'Venta pedido #32'),
    (204, 2, 8, 33, N'SALIDA', 2, '2026-11-03T15:21:00', N'Venta pedido #33'),
    (205, 23, 8, 33, N'SALIDA', 3, '2026-11-03T15:21:00', N'Venta pedido #33'),
    (206, 11, 8, 33, N'SALIDA', 3, '2026-11-03T15:21:00', N'Venta pedido #33'),
    (207, 8, 4, 34, N'SALIDA', 3, '2026-11-18T12:46:00', N'Venta pedido #34'),
    (208, 40, 4, 34, N'SALIDA', 3, '2026-11-18T12:46:00', N'Venta pedido #34'),
    (209, 46, 4, 34, N'SALIDA', 3, '2026-11-18T12:46:00', N'Venta pedido #34'),
    (210, 18, 4, 34, N'SALIDA', 1, '2026-11-18T12:46:00', N'Venta pedido #34'),
    (211, 8, 1, 34, N'DEVOLUCION', 3, '2026-11-18T17:46:00', N'Cancelación pedido #34'),
    (212, 40, 1, 34, N'DEVOLUCION', 3, '2026-11-18T17:46:00', N'Cancelación pedido #34'),
    (213, 46, 1, 34, N'DEVOLUCION', 3, '2026-11-18T17:46:00', N'Cancelación pedido #34'),
    (214, 18, 1, 34, N'DEVOLUCION', 1, '2026-11-18T17:46:00', N'Cancelación pedido #34'),
    (215, 37, 5, 35, N'SALIDA', 1, '2026-11-21T10:06:00', N'Venta pedido #35'),
    (216, 18, 5, 35, N'SALIDA', 2, '2026-11-21T10:06:00', N'Venta pedido #35'),
    (217, 43, 5, 35, N'SALIDA', 1, '2026-11-21T10:06:00', N'Venta pedido #35'),
    (218, 36, 5, 35, N'SALIDA', 2, '2026-11-21T10:06:00', N'Venta pedido #35'),
    (219, 9, 5, 35, N'SALIDA', 1, '2026-11-21T10:06:00', N'Venta pedido #35'),
    (220, 44, 6, 36, N'SALIDA', 2, '2026-11-23T18:41:00', N'Venta pedido #36'),
    (221, 4, 6, 36, N'SALIDA', 3, '2026-11-23T18:41:00', N'Venta pedido #36'),
    (222, 42, 7, 37, N'SALIDA', 3, '2026-11-25T11:11:00', N'Venta pedido #37'),
    (223, 41, 7, 37, N'SALIDA', 2, '2026-11-25T11:11:00', N'Venta pedido #37'),
    (224, 7, 7, 37, N'SALIDA', 2, '2026-11-25T11:11:00', N'Venta pedido #37');
SET IDENTITY_INSERT MOVIMIENTO_INVENTARIO OFF;

-- ======================== 9. RESEÑAS ========================

-- Solo de productos comprados en pedidos Entregados (5); una por cliente y producto
SET IDENTITY_INSERT RESENA ON;
INSERT INTO RESENA (idResena, idCliente, idProducto, calificacion, comentario, fechaResena) VALUES
    (1, 1, 33, 2, NULL, '2026-01-07T09:00:00'),
    (2, 2, 15, 5, N'Perfecto, llegó rápido.', '2026-01-14T10:13:00'),
    (3, 3, 47, 4, N'Buena relación calidad-precio.', '2026-01-21T11:26:00'),
    (4, 3, 29, 3, N'Está bien para el precio.', '2026-01-21T11:26:00'),
    (5, 9, 24, 4, N'Muy bueno, aunque la talla es un poco pequeña.', '2026-03-13T17:44:00'),
    (6, 9, 2, 3, N'Cumple, pero esperaba algo mejor.', '2026-03-13T17:44:00'),
    (7, 10, 35, 4, N'Buena relación calidad-precio.', '2026-04-20T09:57:00'),
    (8, 11, 39, 4, N'Muy bueno, aunque la talla es un poco pequeña.', '2026-04-27T10:10:00'),
    (9, 13, 50, 4, N'Buena relación calidad-precio.', '2026-05-16T12:36:00'),
    (10, 13, 33, 4, N'Muy bueno, aunque la talla es un poco pequeña.', '2026-05-16T12:36:00'),
    (11, 14, 45, 4, N'Muy bueno, aunque la talla es un poco pequeña.', '2026-05-23T13:49:00'),
    (12, 4, 10, 5, N'Perfecto, llegó rápido.', '2026-07-08T09:54:00'),
    (13, 5, 15, 5, N'Excelente calidad, lo recomiendo.', '2026-07-15T10:07:00'),
    (14, 5, 48, 5, N'Excelente calidad, lo recomiendo.', '2026-07-15T10:07:00'),
    (15, 9, 50, 5, N'Excelente calidad, lo recomiendo.', '2026-08-18T14:59:00'),
    (16, 9, 29, 4, N'Buena relación calidad-precio.', '2026-08-18T14:59:00'),
    (17, 7, 46, 5, N'Superó mis expectativas.', '2026-08-29T12:33:00'),
    (18, 10, 31, 5, N'Superó mis expectativas.', '2026-09-25T15:12:00'),
    (19, 13, 47, 3, N'Está bien para el precio.', '2026-10-21T09:51:00'),
    (20, 7, 2, 3, N'Cumple, pero esperaba algo mejor.', '2026-11-09T15:20:00');
SET IDENTITY_INSERT RESENA OFF;

-- ===================================================================================
-- 10. CASOS DE PRUEBA
--     Todo lo anterior es la tienda "normal". Aquí se preparan, a propósito, los casos
--     que necesitan las pruebas (07_pruebas.sql) y los reportes. Cada uno se arma igual
--     que en la vida real: un AJUSTE de inventario (con su movimiento) o un UPDATE.
--     Los ID de estos movimientos los pone SQL Server (IDENTITY), ya no se fuerzan.
-- ===================================================================================

-- Caso: Agotado: pruebas 2 y 3 (compra sin stock)
--       Producto 2 (CAL-ADI-002 - Tenis de correr Adidas Ultraboost): 11 -> 0 unidades
INSERT INTO MOVIMIENTO_INVENTARIO (idInventario, idUsuario, idPedido, tipoMovimiento, cantidad, fechaMovimiento, motivo)
VALUES (2, 1, NULL, 'AJUSTE', -11, '2026-11-24T17:00:00', N'Ajuste por mercadería dañada');
UPDATE INVENTARIO SET cantidadDisponible = cantidadDisponible + (-11), ultimaActualizacion = '2026-11-24T17:00:00'
WHERE idProducto = 2;

-- Caso: Stock 1: prueba 10 (dos compras simultáneas)
--       Producto 16 (RAQ-WIL-016 - Raqueta de tenis Wilson Clash 100): 38 -> 1 unidades
INSERT INTO MOVIMIENTO_INVENTARIO (idInventario, idUsuario, idPedido, tipoMovimiento, cantidad, fechaMovimiento, motivo)
VALUES (16, 1, NULL, 'AJUSTE', -37, '2026-11-24T17:00:00', N'Devolución al proveedor por lote defectuoso');
UPDATE INVENTARIO SET cantidadDisponible = cantidadDisponible + (-37), ultimaActualizacion = '2026-11-24T17:00:00'
WHERE idProducto = 16;

-- Caso: Bajo el mínimo: R6 / vw_ExistenciasBajas
--       Producto 12 (BAL-NIK-012 - Balón de fútbol Nike Strike): 76 -> 2 unidades
INSERT INTO MOVIMIENTO_INVENTARIO (idInventario, idUsuario, idPedido, tipoMovimiento, cantidad, fechaMovimiento, motivo)
VALUES (12, 1, NULL, 'AJUSTE', -74, '2026-11-24T17:00:00', N'Devolución al proveedor por lote defectuoso');
UPDATE INVENTARIO SET cantidadDisponible = cantidadDisponible + (-74), ultimaActualizacion = '2026-11-24T17:00:00'
WHERE idProducto = 12;

-- Caso: Bajo el mínimo: R6 / vw_ExistenciasBajas
--       Producto 23 (FIT-ADI-023 - Set de bandas de resistencia Adidas): 51 -> 3 unidades
INSERT INTO MOVIMIENTO_INVENTARIO (idInventario, idUsuario, idPedido, tipoMovimiento, cantidad, fechaMovimiento, motivo)
VALUES (23, 1, NULL, 'AJUSTE', -48, '2026-11-24T17:00:00', N'Devolución al proveedor por lote defectuoso');
UPDATE INVENTARIO SET cantidadDisponible = cantidadDisponible + (-48), ultimaActualizacion = '2026-11-24T17:00:00'
WHERE idProducto = 23;

-- Caso: Bajo el mínimo: R6 / vw_ExistenciasBajas
--       Producto 41 (CAM-UAR-041 - Mochila de senderismo Under Armour 30 L): 35 -> 2 unidades
INSERT INTO MOVIMIENTO_INVENTARIO (idInventario, idUsuario, idPedido, tipoMovimiento, cantidad, fechaMovimiento, motivo)
VALUES (41, 1, NULL, 'AJUSTE', -33, '2026-11-24T17:00:00', N'Devolución al proveedor por lote defectuoso');
UPDATE INVENTARIO SET cantidadDisponible = cantidadDisponible + (-33), ultimaActualizacion = '2026-11-24T17:00:00'
WHERE idProducto = 41;

-- Caso: Exactamente en el mínimo: NO debe salir en existencias bajas
--       Producto 30 (CIC-ADI-030 - Gafas de ciclismo Adidas): 29 -> 4 unidades
INSERT INTO MOVIMIENTO_INVENTARIO (idInventario, idUsuario, idPedido, tipoMovimiento, cantidad, fechaMovimiento, motivo)
VALUES (30, 1, NULL, 'AJUSTE', -25, '2026-11-24T17:00:00', N'Devolución al proveedor por lote defectuoso');
UPDATE INVENTARIO SET cantidadDisponible = cantidadDisponible + (-25), ultimaActualizacion = '2026-11-24T17:00:00'
WHERE idProducto = 30;

-- Caso: producto descontinuado (filtro "solo activos" y vw_CatalogoDisponible).
--       Tuvo ventas antes, así que sus pedidos viejos siguen existiendo (borrado lógico).
UPDATE PRODUCTO SET activo = 0 WHERE idProducto = 50;

-- Caso: cliente desactivado (no tiene pedidos ni debe poder comprar).
UPDATE CLIENTE SET activo = 0 WHERE idCliente = 20;
UPDATE USUARIO SET activo = 0 WHERE idCliente = 20;

-- Caso: dos promociones vigentes sobre el mismo producto (regla: solo se aplica la mayor).
--       El balón 11 ya está en "Temporada de fútbol" (12 %); se agrega a "Black Friday" (25 %).
INSERT INTO PROMOCION_PRODUCTO (idPromocion, idProducto) VALUES (4, 11);

-- Caso (sin código): los clientes 16 a 20 no tienen pedidos -> R8 "clientes sin compras".


COMMIT;
GO

/* ==========================================================================================
   VERIFICACIONES (deben correr sin problema y mostrar lo esperado)
   ========================================================================================== */

-- A) Conciliación de inventario (guía del equipo). Si devuelve 0 filas, todo cuadra.
SELECT i.idProducto, i.cantidadDisponible,
       SUM(CASE WHEN m.tipoMovimiento = 'SALIDA' THEN -m.cantidad ELSE m.cantidad END) AS segunMovimientos
FROM INVENTARIO i
JOIN MOVIMIENTO_INVENTARIO m ON m.idInventario = i.idInventario
GROUP BY i.idProducto, i.cantidadDisponible
HAVING i.cantidadDisponible <> SUM(CASE WHEN m.tipoMovimiento = 'SALIDA' THEN -m.cantidad ELSE m.cantidad END);

-- B) Conteos mínimos que pide la especificación
SELECT 'Marcas' AS dato, COUNT(*) AS cantidad, 10 AS minimo FROM MARCA
UNION ALL SELECT 'Categorías', COUNT(*), 10 FROM CATEGORIA
UNION ALL SELECT 'Productos con existencia', COUNT(*), 50 FROM INVENTARIO
UNION ALL SELECT 'Clientes', COUNT(*), 20 FROM CLIENTE
UNION ALL SELECT 'Pedidos', COUNT(*), 30 FROM PEDIDO
UNION ALL SELECT 'Clientes con 2+ pedidos', COUNT(*), 15
          FROM (SELECT idCliente FROM PEDIDO GROUP BY idCliente HAVING COUNT(*) >= 2) x
UNION ALL SELECT 'Meses distintos con pedidos', COUNT(DISTINCT MONTH(fechaPedido)), 2 FROM PEDIDO
UNION ALL SELECT 'Promociones', COUNT(*), 5 FROM PROMOCION
UNION ALL SELECT 'Promociones vigentes hoy', COUNT(*), 1 FROM PROMOCION
          WHERE SYSDATETIME() BETWEEN fechaInicio AND fechaFin
UNION ALL SELECT 'Promociones vencidas', COUNT(*), 1 FROM PROMOCION WHERE fechaFin < SYSDATETIME()
UNION ALL SELECT 'Reseñas', COUNT(*), 20 FROM RESENA
UNION ALL SELECT 'Movimientos de inventario', COUNT(*), 30 FROM MOVIMIENTO_INVENTARIO
UNION ALL SELECT 'Productos bajo el mínimo', COUNT(*), 5 FROM PRODUCTO p
          JOIN INVENTARIO i ON i.idProducto = p.idProducto WHERE i.cantidadDisponible < p.stockMinimo;

-- C) Toda reseña corresponde a una compra entregada (debe devolver 0 filas)
SELECT r.idResena
FROM RESENA r
WHERE NOT EXISTS (SELECT 1 FROM PEDIDO p JOIN DETALLE_PEDIDO d ON d.idPedido = p.idPedido
                  WHERE p.idCliente = r.idCliente AND d.idProducto = r.idProducto
                    AND p.idEstadoPedido = 5);

-- D) El total de cada pedido coincide con la suma de sus líneas (debe devolver 0 filas)
SELECT p.idPedido
FROM PEDIDO p
JOIN DETALLE_PEDIDO d ON d.idPedido = p.idPedido
GROUP BY p.idPedido, p.subtotalPedido, p.descuentoPedido
HAVING p.subtotalPedido <> SUM(d.cantidad * d.precioUnitario) OR p.descuentoPedido <> SUM(d.descuento);

-- E) Así quedaron los casos de prueba
SELECT p.idProducto, p.sku, p.nombreProducto, i.cantidadDisponible, p.stockMinimo, p.activo,
       CASE WHEN i.cantidadDisponible < p.stockMinimo THEN 'Bajo el mínimo' ELSE 'OK' END AS situacion
FROM PRODUCTO p JOIN INVENTARIO i ON i.idProducto = p.idProducto
WHERE p.idProducto IN (2, 12, 16, 23, 30, 41, 50)
ORDER BY p.idProducto;
GO
