// FreshBox SpA - Frontend CRUD - EP2 EKS
const API_BASE = window.location.origin;
const API_GET = API_BASE + '/api/products';

document.addEventListener('DOMContentLoaded', cargarProductos);

async function cargarProductos() {
    try {
        const response = await fetch(API_GET);
        const productos = await response.json();
        renderizarTabla(productos);
        mostrarMensaje('Productos cargados', 'exito');
    } catch (error) { mostrarMensaje('Error: ' + error.message, 'error'); }
}

function renderizarTabla(productos) {
    const tbody = document.getElementById('productos-body');
    tbody.innerHTML = '';
    if (productos.length === 0) { tbody.innerHTML = '<tr><td colspan="7">No hay productos</td></tr>'; return; }
    productos.forEach(p => {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${p.id}</td><td>${p.nombre}</td><td>${p.descripcion || '-'}</td><td>$${Number(p.precio).toLocaleString('es-CL')}</td><td>${p.stock}</td><td>${p.categoria || '-'}</td><td><button class="btn-editar" onclick="editarProducto(${p.id},'${escapar(p.nombre)}','${escapar(p.descripcion||'')}',${p.precio},${p.stock},'${escapar(p.categoria||'')}')">Editar</button> <button class="btn-eliminar" onclick="eliminarProducto(${p.id})">Eliminar</button></td>`;
        tbody.appendChild(tr);
    });
}

async function guardarProducto(event) {
    event.preventDefault();
    const id = document.getElementById('producto-id').value;
    const datos = { nombre: document.getElementById('nombre').value, descripcion: document.getElementById('descripcion').value, precio: parseFloat(document.getElementById('precio').value), stock: parseInt(document.getElementById('stock').value), categoria: document.getElementById('categoria').value };
    try {
        let response;
        if (id) { response = await fetch(API_GET + '/' + id, { method: 'PUT', headers: {'Content-Type':'application/json'}, body: JSON.stringify(datos) }); }
        else { response = await fetch(API_GET, { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(datos) }); }
        if (!response.ok) throw new Error('Error');
        mostrarMensaje(id ? 'Modificado' : 'Creado', 'exito');
        limpiarFormulario(); cargarProductos();
    } catch (error) { mostrarMensaje('Error: ' + error.message, 'error'); }
}

async function eliminarProducto(id) {
    if (!confirm('Eliminar?')) return;
    await fetch(API_GET + '/' + id, { method: 'DELETE' });
    mostrarMensaje('Eliminado', 'exito'); cargarProductos();
}

function editarProducto(id, n, d, p, s, c) { document.getElementById('producto-id').value=id; document.getElementById('nombre').value=n; document.getElementById('descripcion').value=d; document.getElementById('precio').value=p; document.getElementById('stock').value=s; document.getElementById('categoria').value=c; document.getElementById('form-titulo').textContent='Editar (ID:'+id+')'; }
function cancelarEdicion() { limpiarFormulario(); }
function limpiarFormulario() { document.getElementById('producto-form').reset(); document.getElementById('producto-id').value=''; document.getElementById('form-titulo').textContent='Nuevo Producto'; }
function mostrarMensaje(t, tipo) { const m=document.getElementById('mensaje'); m.textContent=t; m.className=tipo==='exito'?'mensaje-exito':'mensaje-error'; setTimeout(()=>{m.textContent='';m.className='';},4000); }
function escapar(s) { return s.replace(/'/g,"\\'"); }
// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
