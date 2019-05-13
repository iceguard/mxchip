// Copyright (c) Microsoft. All rights reserved.
// Licensed under the MIT license. 
// To get started please visit https://microsoft.github.io/azure-iot-developer-kit/docs/projects/connect-iot-hub?utm_source=ArduinoExtension&utm_medium=ReleaseNote&utm_campaign=VSCode
#include "AZ3166WiFi.h"
#include "AzureIotHub.h"
#include "DevKitMQTTClient.h"

#include "config.h"
#include "utility.h"
#include "auth.h"
#include "SystemTickCounter.h"
#include "parson.h"
#include "Sensor.h"

static bool hasWifi = false;
int messageCount = 1;
static bool messageSending = true;
static uint64_t send_interval_ms;

RGB_LED rgbLed;
static int userLEDState = 0;
static int rgbLEDState = 0;
static int rgbLEDR = 0;
static int rgbLEDG = 0;
static int rgbLEDB = 0;

//////////////////////////////////////////////////////////////////////////////////////////////////////////
// Utilities
static void InitWifi()
{
  Screen.print(2, "Connecting...");

  if (WiFi.begin(WIFI_USER, WIFI_PASS) == WL_CONNECTED 
	|| WiFi.begin() == WL_CONNECTED)
  {
    IPAddress ip = WiFi.localIP();
    Screen.print(1, ip.get_address());
    hasWifi = true;
    Screen.print(2, "Running... \r\n");
  }
  else
  {
    hasWifi = false;
    Screen.print(1, "No Wi-Fi\r\n ");
  }
}

static void SendConfirmationCallback(IOTHUB_CLIENT_CONFIRMATION_RESULT result)
{
  if (result == IOTHUB_CLIENT_CONFIRMATION_OK)
  {
    blinkSendConfirmation();
  }
}

static void MessageCallback(const char* payLoad, int size)
{
  blinkLED();
  Screen.print(1, payLoad, true);
}

void parseTwinMessage(DEVICE_TWIN_UPDATE_STATE updateState, const char *message)
{
    JSON_Value *root_value;
    root_value = json_parse_string(message);
    if (json_value_get_type(root_value) != JSONObject)
    {
        if (root_value != NULL)
        {
            json_value_free(root_value);
        }
        LogError("parse %s failed", message);
        return;
    }
    JSON_Object *root_object = json_value_get_object(root_value);

    if (updateState == DEVICE_TWIN_UPDATE_COMPLETE)
    {
        JSON_Object *desired_object = json_object_get_object(root_object, "desired");
        if (desired_object != NULL)
        {
          if (json_object_has_value(desired_object, "userLEDState"))
          {
            userLEDState = json_object_get_number(desired_object, "userLEDState");
          }
          if (json_object_has_value(desired_object, "rgbLEDState"))
          {
            rgbLEDState = json_object_get_number(desired_object, "rgbLEDState");
          }
          if (json_object_has_value(desired_object, "rgbLEDR"))
          {
            rgbLEDR = json_object_get_number(desired_object, "rgbLEDR");
          }
          if (json_object_has_value(desired_object, "rgbLEDG"))
          {
            rgbLEDG = json_object_get_number(desired_object, "rgbLEDG");
          }
          if (json_object_has_value(desired_object, "rgbLEDB"))
          {
            rgbLEDB = json_object_get_number(desired_object, "rgbLEDB");
          }
        }
    }
    else
    {
      if (json_object_has_value(root_object, "userLEDState"))
      {
        userLEDState = json_object_get_number(root_object, "userLEDState");
      }
      if (json_object_has_value(root_object, "rgbLEDState"))
      {
        rgbLEDState = json_object_get_number(root_object, "rgbLEDState");
      }
      if (json_object_has_value(root_object, "rgbLEDR"))
      {
        rgbLEDR = json_object_get_number(root_object, "rgbLEDR");
      }
      if (json_object_has_value(root_object, "rgbLEDG"))
      {
        rgbLEDG = json_object_get_number(root_object, "rgbLEDG");
      }
      if (json_object_has_value(root_object, "rgbLEDB"))
      {
        rgbLEDB = json_object_get_number(root_object, "rgbLEDB");
      }
    }

    if (rgbLEDState == 0)
    {
      rgbLed.turnOff();
    }
    else
    {
      rgbLed.setColor(rgbLEDR, rgbLEDG, rgbLEDB);
    }

    pinMode(LED_USER, OUTPUT);
    digitalWrite(LED_USER, userLEDState);
    json_value_free(root_value);
}


static void DeviceTwinCallback(DEVICE_TWIN_UPDATE_STATE updateState, const unsigned char *payLoad, int size)
{
  char *temp = (char *)malloc(size + 1);
  if (temp == NULL)
  {
    return;
  }
  memcpy(temp, payLoad, size);
  temp[size] = '\0';
  parseTwinMessage(updateState, temp);
  free(temp);
}

static int  DeviceMethodCallback(const char *methodName, const unsigned char *payload, int size, unsigned char **response, int *response_size)
{
  LogInfo("Try to invoke method %s", methodName);
  const char *responseMessage = "\"Successfully invoke device method\"";
  int result = 200;

  if (strcmp(methodName, "start") == 0)
  {
    LogInfo("Start sending temperature and humidity data");
    messageSending = true;
  }
  else if (strcmp(methodName, "stop") == 0)
  {
    LogInfo("Stop sending temperature and humidity data");
    messageSending = false;
  }
  else
  {
    LogInfo("No method %s found", methodName);
    responseMessage = "\"No method found\"";
    result = 404;
  }

  *response_size = strlen(responseMessage) + 1;
  *response = (unsigned char *)strdup(responseMessage);

  return result;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////
// Arduino sketch
void setup()
{
  Screen.init();
  Screen.print(0, "IoT DevKit");
  Screen.print(2, "Initializing...");
  
  Screen.print(3, " > Serial");
  Serial.begin(115200);

  // Initialize the WiFi module
  Screen.print(3, " > WiFi");
  hasWifi = false;
  InitWifi();
  if (!hasWifi)
  {
    return;
  }

  LogTrace("HappyPathSetup", NULL);

  Screen.print(3, " > Sensors");
  SensorInit();

  Screen.print(3, " > IoT Hub");
  DevKitMQTTClient_SetOption(OPTION_MINI_SOLUTION_NAME, "DevKit-GetStarted");
  DevKitMQTTClient_Init(true);

  DevKitMQTTClient_SetSendConfirmationCallback(SendConfirmationCallback);
  DevKitMQTTClient_SetMessageCallback(MessageCallback);
  DevKitMQTTClient_SetDeviceTwinCallback(DeviceTwinCallback);
  DevKitMQTTClient_SetDeviceMethodCallback(DeviceMethodCallback);

  send_interval_ms = SystemTickCounterRead();
}

void loop()
{
  if (hasWifi)
  {
    if (messageSending && 
        (int)(SystemTickCounterRead() - send_interval_ms) >= getInterval())
    {
      // Send teperature data
      char messagePayload[MESSAGE_MAX_LEN];

      bool temperatureAlert = readMessage(messageCount++, messagePayload);
      EVENT_INSTANCE* message = DevKitMQTTClient_Event_Generate(messagePayload, MESSAGE);
      DevKitMQTTClient_Event_AddProp(message, "temperatureAlert", temperatureAlert ? "true" : "false");
      DevKitMQTTClient_SendEventInstance(message);
      
      send_interval_ms = SystemTickCounterRead();
    }
    else
    {
      DevKitMQTTClient_Check();
    }
    const char *firmwareVersion = getDevkitVersion();
    const char *wifiSSID = WiFi.SSID();
    int wifiRSSI = WiFi.RSSI();
    const char *wifiIP = (const char *)WiFi.localIP().get_address();
    const char *wifiMask = (const char *)WiFi.subnetMask().get_address();
    byte mac[6];
    char macAddress[18];
    if (rgbLEDState == 0)
    {
      rgbLed.turnOff();
    }
    else
    {
      rgbLed.setColor(rgbLEDR, rgbLEDG, rgbLEDB);
    }

    pinMode(LED_USER, OUTPUT);
    digitalWrite(LED_USER, userLEDState);

    char state[500];
    snprintf(state, 500, "{\"wifiSSID\":\"%s\",\"wifiRSSI\":%d,\"wifiIP\":\"%s\",\"wifiMask\":\"%s\",\"macAddress\":\"%s\",\"rgbLEDState\":\"%s\",\"rgbLEDR\":\"%s\",\"rgbLEDG\":\"%s\",\"rgbLEDB\":\"%s\"}", firmwareVersion, wifiSSID, wifiRSSI, wifiIP, wifiMask, macAddress,rgbLEDState,rgbLEDR,rgbLEDG,rgbLEDB);
    DevKitMQTTClient_ReportState(state);
  }
  delay(1000);
}
