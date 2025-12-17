precision mediump float;

varying vec2 v_tex_coord;

void main() {
    // Create a simple, non-animated gradient based on the screen coordinates.
    // This is the most basic test to ensure the shader is compiling and running.
    vec3 final_color = vec3(v_tex_coord.x, v_tex_coord.y, 0.7);

    gl_FragColor = vec4(final_color, 1.0);
}
