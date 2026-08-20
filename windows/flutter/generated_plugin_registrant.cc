//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_blue_plus_winrt/flutter_blue_plus_plugin.h>
#include <flutter_libserialport/flutter_libserialport_plugin.h>
#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>
#include <nsd_windows/nsd_windows_plugin_c_api.h>
#include <permission_handler_windows/permission_handler_windows_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterBluePlusPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterBluePlusPlugin"));
  FlutterLibserialportPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterLibserialportPlugin"));
  FlutterWebRTCPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterWebRTCPlugin"));
  NsdWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("NsdWindowsPluginCApi"));
  PermissionHandlerWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PermissionHandlerWindowsPlugin"));
}
