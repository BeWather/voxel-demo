# Editor de mapas voxel — alternativas de diseño

Objetivo: un editor de mapas estilo voxel hecho en Godot 4.8. Primera meta: una pradera
editable donde se puedan colocar bloques de terreno y elementos como árboles, plantas y rocas,
y guardar/cargar el resultado.

Hay dos decisiones independientes: **cómo se representa y dibuja el terreno** y **cómo se
representan los elementos decorativos** (props).

## 1. Terreno

### A. GridMap + MeshLibrary (nodo nativo de Godot)

Cada tipo de bloque es un ítem de una `MeshLibrary`; el `GridMap` los instancia en una grilla.

- A favor: ya existe, trae edición dentro del editor de Godot, colisiones y navegación incluidas.
- En contra: dibuja los cubos completos, incluidas las caras tapadas por vecinos, así que el
  costo crece con el volumen y no con la superficie. No permite variar color por voxel ni
  oclusión ambiental sin un ítem por variante. La `MeshLibrary` hay que mantenerla a mano o
  generarla con un script aparte.
- Encaja si los bloques son piezas modeladas (tiles 3D), no cubos de color.

### B. Mallas por chunk generadas en GDScript (elegida)

El mundo es un diccionario de chunks de 16×16×16; cada chunk guarda sus voxeles en un
`PackedByteArray` y genera un `ArrayMesh` que solo contiene las caras expuestas, con color por
vértice.

- A favor: control total del aspecto (variación de tono por voxel, oclusión ambiental por
  vértice, agua translúcida), sin assets externos, sin dependencias, y editar un voxel solo
  regenera el chunk afectado. El formato de datos es nuestro, así que guardar/cargar y
  deshacer/rehacer son directos.
- En contra: hay que escribir el mallador, el raycast y el guardado. GDScript limita el tamaño
  práctico del mapa (cómodo hasta unos 128×128×32; más allá conviene pasar el mallador a hilos
  o a C#/GDExtension).

### C. Módulo `godot_voxel` (Zylann)

Motor voxel completo en C++: streaming, LOD, mallado en hilos, terreno liso o cúbico.

- A favor: rendimiento y escala muy superiores; resuelve mundos enormes.
- En contra: requiere un build propio del motor o un GDExtension que debe coincidir con la
  versión exacta de Godot. El proyecto usa 4.8 beta, donde esa compatibilidad no está
  garantizada. Es mucha maquinaria para un editor de mapas acotados.

### D. Un `MultiMesh` de cubos

Cada voxel es una instancia de cubo.

- A favor: trivial de implementar.
- En contra: mismo problema de caras ocultas que GridMap, y además cualquier edición obliga a
  reescribir el buffer de instancias. Solo sirve para prototipos muy chicos.

## 2. Elementos (árboles, plantas, rocas)

### 2a. Estampar los elementos como voxeles del terreno

Un árbol son bloques "tronco" y "hojas" escritos en el mundo.

- A favor: un solo sistema.
- En contra: el elemento pierde identidad (no se puede seleccionar, mover ni borrar como
  unidad) y su detalle queda limitado al tamaño del voxel de terreno: una flor ocuparía un
  bloque entero.

### 2b. Props como objetos con su propio modelo mini-voxel (elegida)

Cada prop es un modelo voxel de resolución más fina (1/8 de bloque) generado por código,
anclado a una celda del terreno, con rotación y variante. Se dibujan con un `MultiMesh` por
modelo.

- A favor: mantiene el estilo voxel con más detalle, cada elemento se coloca y se borra como
  unidad, miles de instancias cuestan pocas draw calls, y más adelante se pueden reemplazar los
  modelos generados por archivos `.vox` de MagicaVoxel sin tocar el resto.
- En contra: dos sistemas de render en vez de uno.

### 2c. Escenas `.tscn`/`.glb` por elemento

- A favor: máxima flexibilidad (animación, scripts por objeto).
- En contra: necesita assets modelados que hoy no existen, y un nodo por elemento escala mal.

## Decisión

**Terreno B + props 2b.** Todo en GDScript, sin assets externos ni dependencias, funcionando en
Godot 4.8 beta tal como está instalado. Los límites conocidos (tamaño de mapa, mallado en el
hilo principal) no afectan a una pradera de 64×64 y tienen salida clara si el proyecto crece.

## Alcance de la primera versión

- Pradera generada: 64×64 celdas con lomas suaves, capas pasto/tierra/piedra, un estanque con
  orilla de arena y vegetación repartida al azar.
- Bloques: pasto, tierra, piedra, arena, agua, nieve, madera, camino.
- Props: roble, pino, arbusto, flores (roja, amarilla, azul), pasto alto, roca, hongo, tronco.
- Herramientas: colocar bloque, borrar bloque, pintar bloque, colocar prop, borrar prop, con
  tamaño de pincel para los bloques.
- Cámara orbital, cursor que resalta la celda apuntada, deshacer/rehacer.
- Guardar y cargar mapas en JSON; generar pradera nueva con otra semilla.

## Fuera de alcance por ahora

- Importar modelos `.vox`.
- Mapas más grandes que 128×128 (requiere mallado en hilos).
- Colisiones y un personaje para recorrer el mapa.
- Exportar el mapa a otros formatos.
