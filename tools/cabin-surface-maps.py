"""Generate packed surface detail for the Aquarius Blender/glTF build."""

import math

import bpy
import numpy as np


def packed_image(name, rgb, non_color=True):
    width, height = rgb.shape[1], rgb.shape[0]
    image = bpy.data.images.get(name)
    if image is None:
        image = bpy.data.images.new(name, width, height, alpha=False)
    elif tuple(image.size) != (width, height):
        image.scale(width, height)
    image.colorspace_settings.name = 'Non-Color' if non_color else 'sRGB'
    rgba = np.ones((height, width, 4), dtype=np.float32)
    rgba[:, :, :3] = rgb
    image.pixels.foreach_set(rgba.ravel())
    image.pack()
    return image


def link_image(material, name, image, target):
    nodes = material.node_tree.nodes
    node = nodes.get(name) or nodes.new('ShaderNodeTexImage')
    node.name = name
    node.label = name
    node.image = image
    material.node_tree.links.new(node.outputs['Color'], target)


def surface_normal(label, width, height, seed, strength, brushed=False):
    rng = np.random.default_rng(seed)
    grains = rng.standard_normal((height, width)).astype(np.float32)
    x = np.arange(width, dtype=np.float32)[None, :] / width
    y = np.arange(height, dtype=np.float32)[:, None] / height
    # Periodic relief also stays continuous on rods and tiled structural faces.
    if brushed:
        grains = 0.3 * grains + np.sin(math.tau * (17 * y + 0.16 * np.sin(math.tau * 3 * x)))
        grains += 0.45 * np.sin(math.tau * (37 * y + 0.35 * np.sin(math.tau * 2 * x)))
    else:
        grains = (2 * grains + np.roll(grains, 1, axis=0) + np.roll(grains, 1, axis=1)) / 4
        grains += 0.7 * np.sin(math.tau * (13 * x + 9 * y)) * np.sin(math.tau * (19 * x - 7 * y))
    dx = (np.roll(grains, 1, axis=1) - np.roll(grains, -1, axis=1)) * strength
    dy = (np.roll(grains, 1, axis=0) - np.roll(grains, -1, axis=0)) * strength
    lengths = np.sqrt(1 + dx * dx + dy * dy)
    rgb = np.stack((dx / lengths, dy / lengths, 1 / lengths), axis=2) * 0.5 + 0.5
    return packed_image('AQ ' + label + ' normal', rgb)


def normal_detail(material, label, width, height, seed, strength, brushed=False):
    texture = surface_normal(label, width, height, seed, strength, brushed)
    link_normal(material, texture)


def link_normal(material, texture):
    nodes = material.node_tree.nodes
    normal = nodes.get('Surface Relief') or nodes.new('ShaderNodeNormalMap')
    normal.name = 'Surface Relief'
    shader = next(node for node in nodes if node.type == 'BSDF_PRINCIPLED')
    link_image(material, 'Tangent-space Normal', texture, normal.inputs['Color'])
    material.node_tree.links.new(normal.outputs['Normal'], shader.inputs['Normal'])


weave_texture = None


def weave_normal(material):
    global weave_texture
    if weave_texture is None:
        steps = np.arange(128, dtype=np.float32) * math.tau / 128
        warp, weft = 12 * steps[None, :], 12 * steps[:, None]
        relief = np.sin(warp)*(.72+.28*np.cos(weft)) + np.sin(weft)*(.72-.28*np.cos(warp))
        dx = (np.roll(relief, 1, axis=1) - np.roll(relief, -1, axis=1)) * .063
        dy = (np.roll(relief, 1, axis=0) - np.roll(relief, -1, axis=0)) * .063
        lengths = np.sqrt(1 + dx*dx + dy*dy)
        weave_texture = packed_image('AQ woven canvas normal', np.stack((dx/lengths, dy/lengths, 1/lengths), axis=2)*.5+.5)
    link_normal(material, weave_texture)


def panel_backlight(material, panel_id, artwork):
    width, height = artwork.size
    rgba = np.empty(width * height * 4, dtype=np.float32)
    artwork.pixels.foreach_get(rgba)
    rgb = rgba.reshape(height, width, 4)[:, :, :3]
    luminance = 0.2126 * rgb[:, :, 0] + 0.7152 * rgb[:, :, 1] + 0.0722 * rgb[:, :, 2]
    # Only the bright printed features transmit the integral backlight.
    mask = np.clip((luminance - 0.34) / 0.48, 0, 1)
    emission = mask[:, :, None] * np.array([0.83, 0.88, 0.78], dtype=np.float32)
    texture = packed_image('AQ panel ' + panel_id + ' backlight mask', emission, non_color=False)
    shader = next(node for node in material.node_tree.nodes if node.type == 'BSDF_PRINCIPLED')
    link_image(material, 'Legend Backlight', texture, shader.inputs['Emission Color'])
    shader.inputs['Emission Strength'].default_value = 0.55
