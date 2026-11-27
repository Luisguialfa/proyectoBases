/*
================================================================================
Proyecto II - Tienda deportiva - Persona 2 (Federick)
sql/dev/03_p2_catalogos.sql

SP de mantenimiento de catalogos: MARCA, CATEGORIA, CLIENTE, DIRECCION,
PRODUCTO, PROMOCION y RESENA.

Convenciones :
  - CREATE OR ALTER para poder volver a correr el script.
  - SET NOCOUNT ON para no enviar filas de "rows affected" a la API.
  - Validar primero y lanzar THROW con mensaje claro en espanol (la web lo muestra
    tal cual). Los numeros son 50100-50198; el 50199 lo reserva 02_datos.sql.
  - Todo SP que modifica datos recibe @idUsuario y usa TRY / BEGIN TRAN /
    COMMIT / CATCH con ROLLBACK.
  - No existe "Eliminar": se desactiva (activo = 0) para no perder el historial
    de pedidos ni de auditoria.

Errores usados:
  50101 Dato obligatorio vacio            50107 El distrito no existe
  50102 Registro duplicado                50108 La direccion no es del cliente
  50103 Registro no encontrado            50109 El cliente no recibio el producto
  50104 Parametro fuera de rango          50110 La imagen ya existe / no existe
  50105 Usuario no valido                 50111 La promocion ya esta asignada
  50106 Un cliente no puede tener 2 usuarios

Decisiones de diseno que hay que poder defender:
  1. sp_Producto_Buscar consulta PRODUCTO/MARCA/CATEGORIA/INVENTARIO directamente
     porque vw_CatalogoDisponible (Persona 4) todavia no existe. La consulta esta
     aislada en un solo SP: cuando la vista exista solo se cambia este SELECT.
  2. La promocion aplicable es la de mayor descuento entre las vigentes; no se
     suman (regla del equipo). Se calcula con OUTER APPLY + TOP 1 y se usa la
     misma formula en Buscar y en ObtenerDetalle. OPTION (RECOMPILE) evita que
     un plan generado para @idMarca = NULL sea malo para @idMarca = 5.
  3. "Una sola imagen principal por producto" no se puede poner como indice
     unico filtrado (el equipo decidio no usarlos), asi que lo garantizan los SP:
     antes de marcar una imagen como principal se bajan a 0 las demas.
  4. "Un cliente con un solo usuario" tampoco es una restriccion de la base.
     sp_Cliente_ValidarUsuarioUnico centraliza la regla: con @modo = 'CREAR' la
     debe llamar la Persona 5 desde sp_Usuario_Registrar ANTES de insertar el
     USUARIO; con @modo = 'VERIFICAR' la llaman los SP de CLIENTE de este archivo.
================================================================================
*/

USE tiendaDeportiva1;
GO

-- ============================================================================
-- MARCA
-- ============================================================================

CREATE OR ALTER PROCEDURE sp_Marca_Insertar
    @nombreMarca NVARCHAR(100),
    @descripcionMarca NVARCHAR(255) = NULL,
    @idUsuario INT,
    @idMarca INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Se recorta el texto para que " Nike " y "Nike" no sean dos marcas distintas.
    SET @nombreMarca = LTRIM(RTRIM(@nombreMarca));

    IF @nombreMarca IS NULL OR @nombreMarca = ''
        THROW 50101, N'El nombre de la marca es obligatorio.', 1;
    IF EXISTS (SELECT 1 FROM MARCA WHERE nombreMarca = @nombreMarca)
        THROW 50102, N'Ya existe una marca con ese nombre.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            INSERT INTO MARCA (nombreMarca, descripcionMarca)
            VALUES (@nombreMarca, @descripcionMarca);
            SET @idMarca = SCOPE_IDENTITY();
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Marca_Actualizar
    @idMarca INT,
    @nombreMarca NVARCHAR(100),
    @descripcionMarca NVARCHAR(255) = NULL,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    SET @nombreMarca = LTRIM(RTRIM(@nombreMarca));

    IF @idMarca IS NULL OR NOT EXISTS (SELECT 1 FROM MARCA WHERE idMarca = @idMarca)
        THROW 50103, N'La marca no existe.', 1;
    IF @nombreMarca IS NULL OR @nombreMarca = ''
        THROW 50101, N'El nombre de la marca es obligatorio.', 1;
    IF EXISTS (SELECT 1 FROM MARCA WHERE nombreMarca = @nombreMarca AND idMarca <> @idMarca)
        THROW 50102, N'Ya existe otra marca con ese nombre.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            UPDATE MARCA
               SET nombreMarca = @nombreMarca,
                   descripcionMarca = @descripcionMarca
             WHERE idMarca = @idMarca;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Marca_Desactivar
    @idMarca INT,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idMarca IS NULL OR NOT EXISTS (SELECT 1 FROM MARCA WHERE idMarca = @idMarca)
        THROW 50103, N'La marca no existe.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    -- Borrado logico: los pedidos antiguos siguen mostrando su marca.
    BEGIN TRY
        BEGIN TRAN;
            UPDATE MARCA SET activo = 0 WHERE idMarca = @idMarca;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Marca_Activar
    @idMarca INT,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idMarca IS NULL OR NOT EXISTS (SELECT 1 FROM MARCA WHERE idMarca = @idMarca)
        THROW 50103, N'La marca no existe.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            UPDATE MARCA SET activo = 1 WHERE idMarca = @idMarca;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Marca_Listar
    @texto NVARCHAR(100) = NULL,
    @soloActivos BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    -- @soloActivos = 1 (por defecto) muestra solo lo vendible; 0 o NULL muestra todo.
    SELECT idMarca, nombreMarca, descripcionMarca, activo
      FROM MARCA
     WHERE (@texto IS NULL OR nombreMarca LIKE N'%' + @texto + N'%')
       AND (@soloActivos IS NULL OR @soloActivos = 0 OR activo = 1)
     ORDER BY nombreMarca;
END
GO

-- ============================================================================
-- CATEGORIA (la misma logica que MARCA, con sus propios mensajes)
-- ============================================================================

CREATE OR ALTER PROCEDURE sp_Categoria_Insertar
    @nombreCategoria NVARCHAR(100),
    @descripcionCategoria NVARCHAR(255) = NULL,
    @idUsuario INT,
    @idCategoria INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @nombreCategoria = LTRIM(RTRIM(@nombreCategoria));

    IF @nombreCategoria IS NULL OR @nombreCategoria = ''
        THROW 50101, N'El nombre de la categoria es obligatorio.', 1;
    IF EXISTS (SELECT 1 FROM CATEGORIA WHERE nombreCategoria = @nombreCategoria)
        THROW 50102, N'Ya existe una categoria con ese nombre.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            INSERT INTO CATEGORIA (nombreCategoria, descripcionCategoria)
            VALUES (@nombreCategoria, @descripcionCategoria);
            SET @idCategoria = SCOPE_IDENTITY();
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Categoria_Actualizar
    @idCategoria INT,
    @nombreCategoria NVARCHAR(100),
    @descripcionCategoria NVARCHAR(255) = NULL,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    SET @nombreCategoria = LTRIM(RTRIM(@nombreCategoria));

    IF @idCategoria IS NULL OR NOT EXISTS (SELECT 1 FROM CATEGORIA WHERE idCategoria = @idCategoria)
        THROW 50103, N'La categoria no existe.', 1;
    IF @nombreCategoria IS NULL OR @nombreCategoria = ''
        THROW 50101, N'El nombre de la categoria es obligatorio.', 1;
    IF EXISTS (SELECT 1 FROM CATEGORIA WHERE nombreCategoria = @nombreCategoria AND idCategoria <> @idCategoria)
        THROW 50102, N'Ya existe otra categoria con ese nombre.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            UPDATE CATEGORIA
               SET nombreCategoria = @nombreCategoria,
                   descripcionCategoria = @descripcionCategoria
             WHERE idCategoria = @idCategoria;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Categoria_Desactivar
    @idCategoria INT,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idCategoria IS NULL OR NOT EXISTS (SELECT 1 FROM CATEGORIA WHERE idCategoria = @idCategoria)
        THROW 50103, N'La categoria no existe.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            UPDATE CATEGORIA SET activo = 0 WHERE idCategoria = @idCategoria;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Categoria_Activar
    @idCategoria INT,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idCategoria IS NULL OR NOT EXISTS (SELECT 1 FROM CATEGORIA WHERE idCategoria = @idCategoria)
        THROW 50103, N'La categoria no existe.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            UPDATE CATEGORIA SET activo = 1 WHERE idCategoria = @idCategoria;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Categoria_Listar
    @texto NVARCHAR(100) = NULL,
    @soloActivos BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT idCategoria, nombreCategoria, descripcionCategoria, activo
      FROM CATEGORIA
     WHERE (@texto IS NULL OR nombreCategoria LIKE N'%' + @texto + N'%')
       AND (@soloActivos IS NULL OR @soloActivos = 0 OR activo = 1)
     ORDER BY nombreCategoria;
END
GO

-- ============================================================================
-- CLIENTE
-- ============================================================================

CREATE OR ALTER PROCEDURE sp_Cliente_ValidarUsuarioUnico
    @idCliente INT,
    @modo NVARCHAR(20) = N'CREAR'
AS
BEGIN
    SET NOCOUNT ON;

    /*
    Regla de negocio (no es una restriccion de la base): un cliente tiene un
    solo USUARIO. La PK de USUARIO es idUsuario, no idCliente, asi que la base
    no lo impide.

      @modo = 'CREAR'     -> lo llama la Persona 5 antes de sp_Usuario_Registrar:
                            si el cliente ya tiene usuario, no debe crear otro.
      @modo = 'VERIFICAR' -> lo llaman los SP de CLIENTE: si hay mas de uno,
                            hay una inconsistencia que hay que corregir.
    */
    DECLARE @cantidad INT;

    IF @idCliente IS NULL OR NOT EXISTS (SELECT 1 FROM CLIENTE WHERE idCliente = @idCliente)
        THROW 50103, N'El cliente no existe.', 1;

    SELECT @cantidad = COUNT(*) FROM USUARIO WHERE idCliente = @idCliente;

    IF @modo = N'CREAR' AND @cantidad >= 1
        THROW 50106, N'El cliente ya tiene un usuario; no se puede crear otro.', 1;
    IF @modo = N'VERIFICAR' AND @cantidad > 1
        THROW 50106, N'El cliente tiene mas de un usuario; hay que corregirlo antes de editarlo.', 1;
END
GO

CREATE OR ALTER PROCEDURE sp_Cliente_Insertar
    @nombreCliente NVARCHAR(50),
    @apellidoCliente NVARCHAR(50),
    @correoCliente NVARCHAR(100),
    @telefonoCliente NVARCHAR(20) = NULL,
    @idUsuario INT,
    @idCliente INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @nombreCliente = LTRIM(RTRIM(@nombreCliente));
    SET @apellidoCliente = LTRIM(RTRIM(@apellidoCliente));
    SET @correoCliente = LTRIM(RTRIM(@correoCliente));

    IF @nombreCliente IS NULL OR @nombreCliente = ''
        THROW 50101, N'El nombre del cliente es obligatorio.', 1;
    IF @apellidoCliente IS NULL OR @apellidoCliente = ''
        THROW 50101, N'El apellido del cliente es obligatorio.', 1;
    -- La base ya tiene un CHECK con LIKE '%_@_%._%'; aqui damos un mensaje mas claro.
    IF @correoCliente IS NULL OR CHARINDEX(N'@', @correoCliente) = 0
       OR CHARINDEX(N'.', @correoCliente) = 0
        THROW 50104, N'El correo electronico debe tener @ y un dominio con punto.', 1;
    IF EXISTS (SELECT 1 FROM CLIENTE WHERE correoCliente = @correoCliente)
        THROW 50102, N'Ya existe un cliente con ese correo electronico.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    -- Aqui NO se crea USUARIO: esa es la responsabilidad de la Persona 5
    -- (sp_Usuario_Registrar, con el hash de la contrasena).
    BEGIN TRY
        BEGIN TRAN;
            INSERT INTO CLIENTE (nombreCliente, apellidoCliente, correoCliente, telefonoCliente)
            VALUES (@nombreCliente, @apellidoCliente, @correoCliente, @telefonoCliente);
            SET @idCliente = SCOPE_IDENTITY();
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Cliente_Actualizar
    @idCliente INT,
    @nombreCliente NVARCHAR(50),
    @apellidoCliente NVARCHAR(50),
    @correoCliente NVARCHAR(100),
    @telefonoCliente NVARCHAR(20) = NULL,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    SET @nombreCliente = LTRIM(RTRIM(@nombreCliente));
    SET @apellidoCliente = LTRIM(RTRIM(@apellidoCliente));
    SET @correoCliente = LTRIM(RTRIM(@correoCliente));

    IF @idCliente IS NULL OR NOT EXISTS (SELECT 1 FROM CLIENTE WHERE idCliente = @idCliente)
        THROW 50103, N'El cliente no existe.', 1;
    IF @nombreCliente IS NULL OR @nombreCliente = ''
        THROW 50101, N'El nombre del cliente es obligatorio.', 1;
    IF @apellidoCliente IS NULL OR @apellidoCliente = ''
        THROW 50101, N'El apellido del cliente es obligatorio.', 1;
    IF @correoCliente IS NULL OR CHARINDEX(N'@', @correoCliente) = 0
       OR CHARINDEX(N'.', @correoCliente) = 0
        THROW 50104, N'El correo electronico debe tener @ y un dominio con punto.', 1;
    IF EXISTS (SELECT 1 FROM CLIENTE WHERE correoCliente = @correoCliente AND idCliente <> @idCliente)
        THROW 50102, N'Ya existe otro cliente con ese correo electronico.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    EXEC sp_Cliente_ValidarUsuarioUnico @idCliente, N'VERIFICAR';

    BEGIN TRY
        BEGIN TRAN;
            UPDATE CLIENTE
               SET nombreCliente = @nombreCliente,
                   apellidoCliente = @apellidoCliente,
                   correoCliente = @correoCliente,
                   telefonoCliente = @telefonoCliente
             WHERE idCliente = @idCliente;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Cliente_Desactivar
    @idCliente INT,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idCliente IS NULL OR NOT EXISTS (SELECT 1 FROM CLIENTE WHERE idCliente = @idCliente)
        THROW 50103, N'El cliente no existe.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    EXEC sp_Cliente_ValidarUsuarioUnico @idCliente, N'VERIFICAR';

    BEGIN TRY
        BEGIN TRAN;
            UPDATE CLIENTE SET activo = 0 WHERE idCliente = @idCliente;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Cliente_Listar
    @texto NVARCHAR(150) = NULL,
    @soloActivos BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT idCliente,
           nombreCliente,
           apellidoCliente,
           correoCliente,
           telefonoCliente,
           fechaRegistro,
           activo
      FROM CLIENTE
     WHERE (@texto IS NULL OR nombreCliente LIKE N'%' + @texto + N'%'
            OR apellidoCliente LIKE N'%' + @texto + N'%'
            OR correoCliente LIKE N'%' + @texto + N'%')
       AND (@soloActivos IS NULL OR @soloActivos = 0 OR activo = 1)
     ORDER BY apellidoCliente, nombreCliente;
END
GO

CREATE OR ALTER PROCEDURE sp_Cliente_ObtenerPorId
    @idCliente INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Se trae el usuario asociado para que la pantalla de perfil pueda mostrarlo
    -- y para hacer visible la regla "un cliente, un usuario".
    SELECT c.idCliente,
           c.nombreCliente,
           c.apellidoCliente,
           c.correoCliente,
           c.telefonoCliente,
           c.fechaRegistro,
           c.activo,
           u.idUsuario,
           u.nombreUsuario
      FROM CLIENTE c
      LEFT JOIN USUARIO u ON u.idCliente = c.idCliente
     WHERE c.idCliente = @idCliente;
END
GO

-- ============================================================================
-- GEOGRAFIA Y DIRECCION
-- ============================================================================

CREATE OR ALTER PROCEDURE sp_Geografia_Listar
    @idProvincia INT = NULL,
    @idCanton INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Tres conjuntos de resultados para los tres desplegables en cascada de la web.
    SELECT idProvincia, nombreProvincia
      FROM PROVINCIA
     WHERE @idProvincia IS NULL OR idProvincia = @idProvincia
     ORDER BY nombreProvincia;

    SELECT idCanton, idProvincia, nombreCanton
      FROM CANTON
     WHERE (@idProvincia IS NULL OR idProvincia = @idProvincia)
       AND (@idCanton IS NULL OR idCanton = @idCanton)
     ORDER BY nombreCanton;

    SELECT d.idDistrito, d.idCanton, c.idProvincia, d.nombreDistrito
      FROM DISTRITO d
      INNER JOIN CANTON c ON c.idCanton = d.idCanton
     WHERE (@idCanton IS NULL OR d.idCanton = @idCanton)
       AND (@idProvincia IS NULL OR c.idProvincia = @idProvincia)
     ORDER BY d.nombreDistrito;
END
GO

CREATE OR ALTER PROCEDURE sp_Direccion_Insertar
    @idCliente INT,
    @idDistrito INT,
    @otrasReferencia NVARCHAR(255),
    @idUsuario INT,
    @idDireccion INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @otrasReferencia = LTRIM(RTRIM(@otrasReferencia));

    IF @idCliente IS NULL OR NOT EXISTS (SELECT 1 FROM CLIENTE WHERE idCliente = @idCliente)
        THROW 50103, N'El cliente no existe.', 1;
    -- La FK ya lo evita, pero el SP da un mensaje entendible antes de llegar a la base.
    IF @idDistrito IS NULL OR NOT EXISTS (SELECT 1 FROM DISTRITO WHERE idDistrito = @idDistrito)
        THROW 50107, N'El distrito indicado no existe.', 1;
    IF @otrasReferencia IS NULL OR @otrasReferencia = ''
        THROW 50101, N'La referencia de la direccion es obligatoria.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            INSERT INTO DIRECCION (idCliente, idDistrito, otrasReferencia)
            VALUES (@idCliente, @idDistrito, @otrasReferencia);
            SET @idDireccion = SCOPE_IDENTITY();
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Direccion_Actualizar
    @idDireccion INT,
    @idDistrito INT,
    @otrasReferencia NVARCHAR(255),
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    SET @otrasReferencia = LTRIM(RTRIM(@otrasReferencia));

    IF @idDireccion IS NULL OR NOT EXISTS (SELECT 1 FROM DIRECCION WHERE idDireccion = @idDireccion)
        THROW 50103, N'La direccion no existe.', 1;
    IF @idDistrito IS NULL OR NOT EXISTS (SELECT 1 FROM DISTRITO WHERE idDistrito = @idDistrito)
        THROW 50107, N'El distrito indicado no existe.', 1;
    IF @otrasReferencia IS NULL OR @otrasReferencia = ''
        THROW 50101, N'La referencia de la direccion es obligatoria.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            UPDATE DIRECCION
               SET idDistrito = @idDistrito,
                   otrasReferencia = @otrasReferencia
             WHERE idDireccion = @idDireccion;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Direccion_Desactivar
    @idDireccion INT,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idDireccion IS NULL OR NOT EXISTS (SELECT 1 FROM DIRECCION WHERE idDireccion = @idDireccion)
        THROW 50103, N'La direccion no existe.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    -- Se mantiene la fila porque un pedido viejo apunta a esta direccion.
    BEGIN TRY
        BEGIN TRAN;
            UPDATE DIRECCION SET activa = 0 WHERE idDireccion = @idDireccion;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Direccion_Listar
    @idCliente INT,
    @soloActivas BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT d.idDireccion,
           d.idCliente,
           d.idDistrito,
           p.nombreProvincia,
           ca.nombreCanton,
           di.nombreDistrito,
           d.otrasReferencia,
           d.activa
      FROM DIRECCION d
      INNER JOIN DISTRITO di ON di.idDistrito = d.idDistrito
      INNER JOIN CANTON ca ON ca.idCanton = di.idCanton
      INNER JOIN PROVINCIA p ON p.idProvincia = ca.idProvincia
     WHERE d.idCliente = @idCliente
       AND (@soloActivas IS NULL OR @soloActivas = 0 OR d.activa = 1)
     ORDER BY d.activa DESC, d.idDireccion;
END
GO

-- ============================================================================
-- PRODUCTO
-- ============================================================================

CREATE OR ALTER PROCEDURE sp_Producto_Insertar
    @idMarca INT,
    @idCategoria INT,
    @sku NVARCHAR(30),
    @nombreProducto NVARCHAR(150),
    @descripcionProducto NVARCHAR(300) = NULL,
    @precioProducto DECIMAL(12,2),
    @costoProducto DECIMAL(12,2),
    @stockMinimo INT = 0,
    @cantidadInicial INT = 0,
    @urlImagenPrincipal NVARCHAR(500) = NULL,
    @idUsuario INT,
    @idProducto INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @sku = LTRIM(RTRIM(@sku));
    SET @nombreProducto = LTRIM(RTRIM(@nombreProducto));

    IF @idMarca IS NULL OR NOT EXISTS (SELECT 1 FROM MARCA WHERE idMarca = @idMarca AND activo = 1)
        THROW 50103, N'La marca no existe o esta desactivada.', 1;
    IF @idCategoria IS NULL OR NOT EXISTS (SELECT 1 FROM CATEGORIA WHERE idCategoria = @idCategoria AND activo = 1)
        THROW 50103, N'La categoria no existe o esta desactivada.', 1;
    IF @sku IS NULL OR @sku = ''
        THROW 50101, N'El SKU del producto es obligatorio.', 1;
    IF @nombreProducto IS NULL OR @nombreProducto = ''
        THROW 50101, N'El nombre del producto es obligatorio.', 1;
    IF EXISTS (SELECT 1 FROM PRODUCTO WHERE sku = @sku)
        THROW 50102, N'Ya existe un producto con ese SKU.', 1;
    IF @precioProducto IS NULL OR @precioProducto <= 0
        THROW 50104, N'El precio del producto debe ser mayor que cero.', 1;
    IF @costoProducto IS NULL OR @costoProducto < 0
        THROW 50104, N'El costo del producto no puede ser negativo.', 1;
    IF @stockMinimo IS NULL OR @stockMinimo < 0
        THROW 50104, N'El stock minimo no puede ser negativo.', 1;
    IF @cantidadInicial IS NULL OR @cantidadInicial < 0
        THROW 50104, N'La cantidad inicial no puede ser negativa.', 1;
    -- El movimiento ENTRADA se escribe con idUsuario, por eso aqui si se valida
    -- que el usuario exista (las demas operaciones solo reciben el parametro).
    IF @idUsuario IS NULL OR NOT EXISTS (SELECT 1 FROM USUARIO WHERE idUsuario = @idUsuario)
        THROW 50105, N'El usuario que realiza el cambio no existe.', 1;

    -- PRODUCTO + INVENTARIO + ENTRADA son una sola unidad de trabajo: si falla
    -- el movimiento, no queda un producto sin existencias registradas.
    BEGIN TRY
        BEGIN TRAN;
            INSERT INTO PRODUCTO (idMarca, idCategoria, sku, nombreProducto,
                                  descripcionProducto, precioProducto, costoProducto, stockMinimo)
            VALUES (@idMarca, @idCategoria, @sku, @nombreProducto,
                    @descripcionProducto, @precioProducto, @costoProducto, @stockMinimo);
            SET @idProducto = SCOPE_IDENTITY();

            INSERT INTO INVENTARIO (idProducto, cantidadDisponible, cantidadReservada)
            VALUES (@idProducto, @cantidadInicial, 0);

            -- CK_MOVIMIENTO_cantidad exige cantidad > 0 para ENTRADA, asi que
            -- con stock inicial 0 simplemente no se registra movimiento.
            IF @cantidadInicial > 0
            BEGIN
                DECLARE @idInventarioNuevo INT = SCOPE_IDENTITY();

                INSERT INTO MOVIMIENTO_INVENTARIO (idInventario, idUsuario, tipoMovimiento, cantidad, motivo)
                VALUES (@idInventarioNuevo, @idUsuario, N'ENTRADA', @cantidadInicial,
                        N'Inventario inicial del producto nuevo');
            END

            -- Al crear el producto no puede haber otra imagen principal; se
            -- registra aqui para que el catalogo tenga foto desde el inicio.
            IF @urlImagenPrincipal IS NOT NULL AND LTRIM(RTRIM(@urlImagenPrincipal)) <> ''
                INSERT INTO IMAGEN_PRODUCTO (idProducto, urlImagen, esPrincipal)
                VALUES (@idProducto, LTRIM(RTRIM(@urlImagenPrincipal)), 1);
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Producto_Actualizar
    @idProducto INT,
    @idMarca INT,
    @idCategoria INT,
    @sku NVARCHAR(30),
    @nombreProducto NVARCHAR(150),
    @descripcionProducto NVARCHAR(300) = NULL,
    @precioProducto DECIMAL(12,2),
    @costoProducto DECIMAL(12,2),
    @stockMinimo INT = 0,
    @urlImagenPrincipal NVARCHAR(500) = NULL,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    SET @sku = LTRIM(RTRIM(@sku));
    SET @nombreProducto = LTRIM(RTRIM(@nombreProducto));

    IF @idProducto IS NULL OR NOT EXISTS (SELECT 1 FROM PRODUCTO WHERE idProducto = @idProducto)
        THROW 50103, N'El producto no existe.', 1;
    IF @idMarca IS NULL OR NOT EXISTS (SELECT 1 FROM MARCA WHERE idMarca = @idMarca AND activo = 1)
        THROW 50103, N'La marca no existe o esta desactivada.', 1;
    IF @idCategoria IS NULL OR NOT EXISTS (SELECT 1 FROM CATEGORIA WHERE idCategoria = @idCategoria AND activo = 1)
        THROW 50103, N'La categoria no existe o esta desactivada.', 1;
    IF @sku IS NULL OR @sku = ''
        THROW 50101, N'El SKU del producto es obligatorio.', 1;
    IF @nombreProducto IS NULL OR @nombreProducto = ''
        THROW 50101, N'El nombre del producto es obligatorio.', 1;
    IF EXISTS (SELECT 1 FROM PRODUCTO WHERE sku = @sku AND idProducto <> @idProducto)
        THROW 50102, N'Ya existe otro producto con ese SKU.', 1;
    IF @precioProducto IS NULL OR @precioProducto <= 0
        THROW 50104, N'El precio del producto debe ser mayor que cero.', 1;
    IF @costoProducto IS NULL OR @costoProducto < 0
        THROW 50104, N'El costo del producto no puede ser negativo.', 1;
    IF @stockMinimo IS NULL OR @stockMinimo < 0
        THROW 50104, N'El stock minimo no puede ser negativo.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            -- Solo se cambia el precio actual. DETALLE_PEDIDO guarda el precio
            -- historico, por eso los pedidos viejos no se alteran.
            UPDATE PRODUCTO
               SET idMarca = @idMarca,
                   idCategoria = @idCategoria,
                   sku = @sku,
                   nombreProducto = @nombreProducto,
                   descripcionProducto = @descripcionProducto,
                   precioProducto = @precioProducto,
                   costoProducto = @costoProducto,
                   stockMinimo = @stockMinimo
             WHERE idProducto = @idProducto;

            IF @urlImagenPrincipal IS NOT NULL AND LTRIM(RTRIM(@urlImagenPrincipal)) <> ''
            BEGIN
                DECLARE @urlNueva NVARCHAR(500) = LTRIM(RTRIM(@urlImagenPrincipal));
                DECLARE @idImagenExistente INT;

                SELECT @idImagenExistente = idImagen
                  FROM IMAGEN_PRODUCTO
                 WHERE idProducto = @idProducto AND urlImagen = @urlNueva;

                IF @idImagenExistente IS NULL
                BEGIN
                    -- Regla "una sola imagen principal": primero se bajan las
                    -- demas y luego se inserta la nueva como principal.
                    UPDATE IMAGEN_PRODUCTO SET esPrincipal = 0
                     WHERE idProducto = @idProducto AND esPrincipal = 1;

                    INSERT INTO IMAGEN_PRODUCTO (idProducto, urlImagen, esPrincipal)
                    VALUES (@idProducto, @urlNueva, 1);
                END
                ELSE
                BEGIN
                    -- Si la URL ya era secundaria, solo se promueve y se baja
                    -- la principal anterior en el mismo UPDATE.
                    UPDATE IMAGEN_PRODUCTO
                       SET esPrincipal = CASE WHEN idImagen = @idImagenExistente THEN 1 ELSE 0 END
                     WHERE idProducto = @idProducto;
                END
            END
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Producto_Desactivar
    @idProducto INT,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idProducto IS NULL OR NOT EXISTS (SELECT 1 FROM PRODUCTO WHERE idProducto = @idProducto)
        THROW 50103, N'El producto no existe.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    -- No se borra: si ya aparece en pedidos, borrarlo romperia el historial.
    BEGIN TRY
        BEGIN TRAN;
            UPDATE PRODUCTO SET activo = 0 WHERE idProducto = @idProducto;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Producto_Activar
    @idProducto INT,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idProducto IS NULL OR NOT EXISTS (SELECT 1 FROM PRODUCTO WHERE idProducto = @idProducto)
        THROW 50103, N'El producto no existe.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            UPDATE PRODUCTO SET activo = 1 WHERE idProducto = @idProducto;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Producto_Buscar
    @texto NVARCHAR(150) = NULL,
    @idMarca INT = NULL,
    @idCategoria INT = NULL,
    @precioMin DECIMAL(12,2) = NULL,
    @precioMax DECIMAL(12,2) = NULL,
    @soloOfertas BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @texto IS NOT NULL AND LTRIM(RTRIM(@texto)) = '' SET @texto = NULL;

    /*
    Consulta directa porque vw_CatalogoDisponible (Persona 4) aun no existe.
    Filtros opcionales sin SQL dinamico: (@x IS NULL OR columna = @x).
    OPTION (RECOMPILE) permite que SQL Server simplifique la condicion segun
    los parametros que lleguen en cada llamada.
    */
    SELECT p.idProducto,
           p.sku,
           p.nombreProducto,
           m.nombreMarca,
           c.nombreCategoria,
           p.precioProducto,
           CAST(CASE WHEN oferta.descuento IS NULL THEN p.precioProducto
                     WHEN p.precioProducto - oferta.descuento < 0 THEN 0
                     ELSE p.precioProducto - oferta.descuento
                END AS DECIMAL(12,2)) AS precioFinal,
           i.cantidadDisponible,
           ISNULL(r.calificacionPromedio, 0) AS calificacionPromedio,
           ISNULL(img.urlImagen, imgCualquiera.urlImagen) AS urlImagenPrincipal
      FROM PRODUCTO p
      INNER JOIN MARCA m ON m.idMarca = p.idMarca
      INNER JOIN CATEGORIA c ON c.idCategoria = p.idCategoria
      INNER JOIN INVENTARIO i ON i.idProducto = p.idProducto
      LEFT JOIN (SELECT idProducto, AVG(CAST(calificacion AS DECIMAL(10,2))) AS calificacionPromedio
                   FROM RESENA GROUP BY idProducto) r ON r.idProducto = p.idProducto
      LEFT JOIN IMAGEN_PRODUCTO img ON img.idProducto = p.idProducto AND img.esPrincipal = 1
      LEFT JOIN IMAGEN_PRODUCTO imgCualquiera ON imgCualquiera.idProducto = p.idProducto
                                            AND imgCualquiera.idImagen = (SELECT MIN(idImagen)
                                                                            FROM IMAGEN_PRODUCTO
                                                                           WHERE idProducto = p.idProducto)
      -- Solo la mejor promocion vigente (porcentaje o monto), nunca la suma.
      OUTER APPLY (
          SELECT TOP (1) pr.idPromocion,
                         CASE WHEN pr.tipoDescuento = N'PORCENTAJE'
                              THEN ROUND(p.precioProducto * pr.valorDescuento / 100, 2)
                              ELSE pr.valorDescuento
                         END AS descuento
            FROM PROMOCION_PRODUCTO pp
            INNER JOIN PROMOCION pr ON pr.idPromocion = pp.idPromocion
           WHERE pp.idProducto = p.idProducto
             AND pr.activa = 1
             AND SYSDATETIME() BETWEEN pr.fechaInicio AND pr.fechaFin
           ORDER BY CASE WHEN pr.tipoDescuento = N'PORCENTAJE'
                         THEN ROUND(p.precioProducto * pr.valorDescuento / 100, 2)
                         ELSE pr.valorDescuento END DESC,
                    pr.idPromocion
      ) AS oferta
     WHERE p.activo = 1
       AND m.activo = 1
       AND c.activo = 1
       AND (@texto IS NULL OR p.nombreProducto LIKE N'%' + @texto + N'%'
            OR p.sku LIKE N'%' + @texto + N'%')
       AND (@idMarca IS NULL OR p.idMarca = @idMarca)
       AND (@idCategoria IS NULL OR p.idCategoria = @idCategoria)
       AND (@precioMin IS NULL OR p.precioProducto >= @precioMin)
       AND (@precioMax IS NULL OR p.precioProducto <= @precioMax)
       AND (@soloOfertas IS NULL OR @soloOfertas = 0 OR oferta.descuento IS NOT NULL)
     ORDER BY p.nombreProducto
     OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE sp_Producto_ObtenerDetalle
    @idProducto INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idProducto IS NULL OR NOT EXISTS (SELECT 1 FROM PRODUCTO WHERE idProducto = @idProducto)
        THROW 50103, N'El producto no existe.', 1;

    -- Resultado 1: ficha del producto (datos + stock + calificacion + mejor oferta).
    SELECT p.idProducto,
           p.sku,
           p.nombreProducto,
           p.descripcionProducto,
           m.nombreMarca,
           c.nombreCategoria,
           p.precioProducto,
           p.costoProducto,
           p.stockMinimo,
           p.activo,
           i.cantidadDisponible,
           i.cantidadReservada,
           ISNULL(r.calificacionPromedio, 0) AS calificacionPromedio,
           ISNULL(img.urlImagen, imgCualquiera.urlImagen) AS urlImagenPrincipal,
           CASE WHEN oferta.descuento IS NULL THEN p.precioProducto
                WHEN p.precioProducto - oferta.descuento < 0 THEN 0
                ELSE p.precioProducto - oferta.descuento
           END AS precioFinal,
           oferta.idPromocion,
           oferta.nombrePromocion,
           oferta.tipoDescuento,
           oferta.valorDescuento,
           oferta.descuento AS descuentoAplicado,
           oferta.fechaInicio,
           oferta.fechaFin
      FROM PRODUCTO p
      INNER JOIN MARCA m ON m.idMarca = p.idMarca
      INNER JOIN CATEGORIA c ON c.idCategoria = p.idCategoria
      INNER JOIN INVENTARIO i ON i.idProducto = p.idProducto
      LEFT JOIN (SELECT idProducto, AVG(CAST(calificacion AS DECIMAL(10,2))) AS calificacionPromedio
                   FROM RESENA GROUP BY idProducto) r ON r.idProducto = p.idProducto
      LEFT JOIN IMAGEN_PRODUCTO img ON img.idProducto = p.idProducto AND img.esPrincipal = 1
      LEFT JOIN IMAGEN_PRODUCTO imgCualquiera ON imgCualquiera.idProducto = p.idProducto
                                            AND imgCualquiera.idImagen = (SELECT MIN(idImagen)
                                                                            FROM IMAGEN_PRODUCTO
                                                                           WHERE idProducto = p.idProducto)
      OUTER APPLY (
          SELECT TOP (1) pr.idPromocion,
                         pr.nombrePromocion,
                         pr.tipoDescuento,
                         pr.valorDescuento,
                         pr.fechaInicio,
                         pr.fechaFin,
                         CASE WHEN pr.tipoDescuento = N'PORCENTAJE'
                              THEN ROUND(p.precioProducto * pr.valorDescuento / 100, 2)
                              ELSE pr.valorDescuento
                         END AS descuento
            FROM PROMOCION_PRODUCTO pp
            INNER JOIN PROMOCION pr ON pr.idPromocion = pp.idPromocion
           WHERE pp.idProducto = p.idProducto
             AND pr.activa = 1
             AND SYSDATETIME() BETWEEN pr.fechaInicio AND pr.fechaFin
           ORDER BY CASE WHEN pr.tipoDescuento = N'PORCENTAJE'
                         THEN ROUND(p.precioProducto * pr.valorDescuento / 100, 2)
                         ELSE pr.valorDescuento END DESC,
                    pr.idPromocion
      ) AS oferta
     WHERE p.idProducto = @idProducto;

    -- Resultado 2: galeria de imagenes del producto.
    SELECT idImagen, urlImagen, esPrincipal
      FROM IMAGEN_PRODUCTO
     WHERE idProducto = @idProducto
     ORDER BY esPrincipal DESC, idImagen;
END
GO

CREATE OR ALTER PROCEDURE sp_Producto_Imagen_Agregar
    @idProducto INT,
    @urlImagen NVARCHAR(500),
    @esPrincipal BIT = 0,
    @idUsuario INT,
    @idImagen INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @urlImagen = LTRIM(RTRIM(@urlImagen));

    IF @idProducto IS NULL OR NOT EXISTS (SELECT 1 FROM PRODUCTO WHERE idProducto = @idProducto)
        THROW 50103, N'El producto no existe.', 1;
    IF @urlImagen IS NULL OR @urlImagen = ''
        THROW 50101, N'La URL de la imagen es obligatoria.', 1;
    IF EXISTS (SELECT 1 FROM IMAGEN_PRODUCTO WHERE idProducto = @idProducto AND urlImagen = @urlImagen)
        THROW 50110, N'Ese producto ya tiene esa imagen.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            IF @esPrincipal = 1
                UPDATE IMAGEN_PRODUCTO SET esPrincipal = 0
                 WHERE idProducto = @idProducto AND esPrincipal = 1;

            INSERT INTO IMAGEN_PRODUCTO (idProducto, urlImagen, esPrincipal)
            VALUES (@idProducto, @urlImagen, @esPrincipal);
            SET @idImagen = SCOPE_IDENTITY();
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Producto_Imagen_EstablecerPrincipal
    @idImagen INT,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idImagen IS NULL OR NOT EXISTS (SELECT 1 FROM IMAGEN_PRODUCTO WHERE idImagen = @idImagen)
        THROW 50110, N'La imagen no existe.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    DECLARE @idProductoImagen INT;
    SELECT @idProductoImagen = idProducto FROM IMAGEN_PRODUCTO WHERE idImagen = @idImagen;

    -- Un solo UPDATE garantiza que la imagen elegida sea la unica principal.
    BEGIN TRY
        BEGIN TRAN;
            UPDATE IMAGEN_PRODUCTO
               SET esPrincipal = CASE WHEN idImagen = @idImagen THEN 1 ELSE 0 END
             WHERE idProducto = @idProductoImagen;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- ============================================================================
-- PROMOCION
-- ============================================================================

CREATE OR ALTER PROCEDURE sp_Promocion_Insertar
    @nombrePromocion NVARCHAR(100),
    @descripcionPromocion NVARCHAR(255) = NULL,
    @tipoDescuento NVARCHAR(20),
    @valorDescuento DECIMAL(12,2),
    @fechaInicio DATETIME2,
    @fechaFin DATETIME2,
    @activa BIT = 1,
    @idUsuario INT,
    @idPromocion INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @nombrePromocion = LTRIM(RTRIM(@nombrePromocion));
    SET @tipoDescuento = UPPER(LTRIM(RTRIM(@tipoDescuento)));

    IF @nombrePromocion IS NULL OR @nombrePromocion = ''
        THROW 50101, N'El nombre de la promocion es obligatorio.', 1;
    IF @tipoDescuento NOT IN (N'PORCENTAJE', N'MONTO')
        THROW 50104, N'El tipo de descuento debe ser PORCENTAJE o MONTO.', 1;
    IF @valorDescuento IS NULL OR @valorDescuento <= 0
        THROW 50104, N'El valor del descuento debe ser mayor que cero.', 1;
    IF @tipoDescuento = N'PORCENTAJE' AND @valorDescuento > 100
        THROW 50104, N'Un descuento por porcentaje no puede superar 100.', 1;
    IF @fechaInicio IS NULL OR @fechaFin IS NULL OR @fechaFin <= @fechaInicio
        THROW 50104, N'La fecha fin debe ser mayor que la fecha inicio.', 1;
    IF EXISTS (SELECT 1 FROM PROMOCION WHERE nombrePromocion = @nombrePromocion)
        THROW 50102, N'Ya existe una promocion con ese nombre.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            INSERT INTO PROMOCION (nombrePromocion, descripcionPromocion, tipoDescuento,
                                   valorDescuento, fechaInicio, fechaFin, activa)
            VALUES (@nombrePromocion, @descripcionPromocion, @tipoDescuento,
                    @valorDescuento, @fechaInicio, @fechaFin, @activa);
            SET @idPromocion = SCOPE_IDENTITY();
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Promocion_Actualizar
    @idPromocion INT,
    @nombrePromocion NVARCHAR(100),
    @descripcionPromocion NVARCHAR(255) = NULL,
    @tipoDescuento NVARCHAR(20),
    @valorDescuento DECIMAL(12,2),
    @fechaInicio DATETIME2,
    @fechaFin DATETIME2,
    @activa BIT = 1,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    SET @nombrePromocion = LTRIM(RTRIM(@nombrePromocion));
    SET @tipoDescuento = UPPER(LTRIM(RTRIM(@tipoDescuento)));

    IF @idPromocion IS NULL OR NOT EXISTS (SELECT 1 FROM PROMOCION WHERE idPromocion = @idPromocion)
        THROW 50103, N'La promocion no existe.', 1;
    IF @nombrePromocion IS NULL OR @nombrePromocion = ''
        THROW 50101, N'El nombre de la promocion es obligatorio.', 1;
    IF @tipoDescuento NOT IN (N'PORCENTAJE', N'MONTO')
        THROW 50104, N'El tipo de descuento debe ser PORCENTAJE o MONTO.', 1;
    IF @valorDescuento IS NULL OR @valorDescuento <= 0
        THROW 50104, N'El valor del descuento debe ser mayor que cero.', 1;
    IF @tipoDescuento = N'PORCENTAJE' AND @valorDescuento > 100
        THROW 50104, N'Un descuento por porcentaje no puede superar 100.', 1;
    IF @fechaInicio IS NULL OR @fechaFin IS NULL OR @fechaFin <= @fechaInicio
        THROW 50104, N'La fecha fin debe ser mayor que la fecha inicio.', 1;
    IF EXISTS (SELECT 1 FROM PROMOCION WHERE nombrePromocion = @nombrePromocion AND idPromocion <> @idPromocion)
        THROW 50102, N'Ya existe otra promocion con ese nombre.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    BEGIN TRY
        BEGIN TRAN;
            UPDATE PROMOCION
               SET nombrePromocion = @nombrePromocion,
                   descripcionPromocion = @descripcionPromocion,
                   tipoDescuento = @tipoDescuento,
                   valorDescuento = @valorDescuento,
                   fechaInicio = @fechaInicio,
                   fechaFin = @fechaFin,
                   activa = @activa
             WHERE idPromocion = @idPromocion;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Promocion_AsignarProducto
    @idPromocion INT,
    @idProducto INT,
    @idUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idPromocion IS NULL OR NOT EXISTS (SELECT 1 FROM PROMOCION WHERE idPromocion = @idPromocion)
        THROW 50103, N'La promocion no existe.', 1;
    IF @idProducto IS NULL OR NOT EXISTS (SELECT 1 FROM PRODUCTO WHERE idProducto = @idProducto)
        THROW 50103, N'El producto no existe.', 1;
    IF EXISTS (SELECT 1 FROM PROMOCION_PRODUCTO
                WHERE idPromocion = @idPromocion AND idProducto = @idProducto)
        THROW 50111, N'La promocion ya esta asignada a ese producto.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    -- Puede haber varias promociones sobre el mismo producto: el buscador elige
    -- la de mayor descuento, por eso no se rechaza una segunda asignacion.
    BEGIN TRY
        BEGIN TRAN;
            INSERT INTO PROMOCION_PRODUCTO (idPromocion, idProducto)
            VALUES (@idPromocion, @idProducto);
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Promocion_Listar
    @texto NVARCHAR(100) = NULL,
    @idProducto INT = NULL,
    @soloVigentes BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.idPromocion,
           p.nombrePromocion,
           p.descripcionPromocion,
           p.tipoDescuento,
           p.valorDescuento,
           p.fechaInicio,
           p.fechaFin,
           p.activa,
           CASE WHEN p.activa = 1 AND SYSDATETIME() BETWEEN p.fechaInicio AND p.fechaFin
                THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS vigenteHoy,
           (SELECT COUNT(*) FROM PROMOCION_PRODUCTO pp WHERE pp.idPromocion = p.idPromocion) AS cantidadProductos
      FROM PROMOCION p
     WHERE (@texto IS NULL OR p.nombrePromocion LIKE N'%' + @texto + N'%')
       AND (@idProducto IS NULL OR EXISTS (SELECT 1 FROM PROMOCION_PRODUCTO pp
                                           WHERE pp.idPromocion = p.idPromocion
                                             AND pp.idProducto = @idProducto))
       AND (@soloVigentes IS NULL OR @soloVigentes = 0
            OR (p.activa = 1 AND SYSDATETIME() BETWEEN p.fechaInicio AND p.fechaFin))
     ORDER BY p.fechaInicio DESC, p.idPromocion;
END
GO

-- ============================================================================
-- RESENA
-- ============================================================================

CREATE OR ALTER PROCEDURE sp_Resena_Insertar
    @idCliente INT,
    @idProducto INT,
    @calificacion INT,
    @comentario NVARCHAR(500) = NULL,
    @idUsuario INT,
    @idResena INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @idCliente IS NULL OR NOT EXISTS (SELECT 1 FROM CLIENTE WHERE idCliente = @idCliente)
        THROW 50103, N'El cliente no existe.', 1;
    IF @idProducto IS NULL OR NOT EXISTS (SELECT 1 FROM PRODUCTO WHERE idProducto = @idProducto)
        THROW 50103, N'El producto no existe.', 1;
    IF @calificacion IS NULL OR @calificacion < 1 OR @calificacion > 5
        THROW 50104, N'La calificacion debe estar entre 1 y 5.', 1;
    IF EXISTS (SELECT 1 FROM RESENA WHERE idCliente = @idCliente AND idProducto = @idProducto)
        THROW 50102, N'Ese cliente ya dejo una resena de este producto.', 1;
    IF @idUsuario IS NULL OR @idUsuario <= 0
        THROW 50105, N'El usuario que realiza el cambio es obligatorio.', 1;

    -- Regla del equipo: solo puede opinar quien recibio el producto. Se usa el
    -- DETALLE_PEDIDO (precio historico) y el estado 5 = Entregado.
    IF NOT EXISTS (SELECT 1
                     FROM DETALLE_PEDIDO dp
                     INNER JOIN PEDIDO p ON p.idPedido = dp.idPedido
                    WHERE dp.idProducto = @idProducto
                      AND p.idCliente = @idCliente
                      AND p.idEstadoPedido = 5)
        THROW 50109, N'Solo puede opinar un cliente que haya recibido este producto en un pedido entregado.', 1;

    BEGIN TRY
        BEGIN TRAN;
            INSERT INTO RESENA (idCliente, idProducto, calificacion, comentario)
            VALUES (@idCliente, @idProducto, @calificacion, @comentario);
            SET @idResena = SCOPE_IDENTITY();
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_Resena_Listar
    @idProducto INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.idResena,
           r.idProducto,
           r.idCliente,
           c.nombreCliente + N' ' + c.apellidoCliente AS nombreCliente,
           r.calificacion,
           r.comentario,
           r.fechaResena
      FROM RESENA r
      INNER JOIN CLIENTE c ON c.idCliente = r.idCliente
     WHERE r.idProducto = @idProducto
     ORDER BY r.fechaResena DESC, r.idResena DESC;
END
GO

PRINT N'Persona 2: SP de catalogos creados/actualizados correctamente en ' + DB_NAME() + N'.';
GO
