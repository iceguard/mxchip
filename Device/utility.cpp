// Copyright (c) Microsoft. All rights reserved.
// Licensed under the MIT license. 

#include <math.h>
#include "HTS221Sensor.h"
#include "Sensor.h"
#include "AzureIotHub.h"
#include "Arduino.h"
#include "parson.h"
#include "config.h"
#include "RGB_LED.h"

#define RGB_LED_BRIGHTNESS 32

//Peripherals
DevI2C *i2c;
HTS221Sensor *sensor;
LSM6DSLSensor *gyro_sensor;

static RGB_LED rgbLed;
static int interval = INTERVAL;

static float round_2dp(float x)
{
    return roundf(x * 100) / 100.0;
}

int getInterval()
{
    return interval;
}

void blinkLED()
{
    rgbLed.turnOff();
    rgbLed.setColor(RGB_LED_BRIGHTNESS, 0, 0);
    delay(500);
    rgbLed.turnOff();
}

void blinkSendConfirmation()
{
    rgbLed.turnOff();
    rgbLed.setColor(0, 0, RGB_LED_BRIGHTNESS);
    delay(500);
    rgbLed.turnOff();
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

    double val = 0;
    if (updateState == DEVICE_TWIN_UPDATE_COMPLETE)
    {
        JSON_Object *desired_object = json_object_get_object(root_object, "desired");
        if (desired_object != NULL)
        {
            val = json_object_get_number(desired_object, "interval");
        }
    }
    else
    {
        val = json_object_get_number(root_object, "interval");
    }
    if (val > 500)
    {
        interval = (int)val;
        LogInfo(">>>Device twin updated: set interval to %d", interval);
    }
    json_value_free(root_value);
}

void SensorInit()
{
    i2c = new DevI2C(D14, D15);
    sensor = new HTS221Sensor(*i2c);
    gyro_sensor = new LSM6DSLSensor(*i2c, D4, D5);
    sensor->init(NULL);
    gyro_sensor->init(NULL);

    gyro_sensor->enableGyroscope();
    gyro_sensor->enableAccelerator();
}

float readTemperature()
{
    sensor->reset();

    float temperature = 0;
    sensor->getTemperature(&temperature);

    return temperature;
}

float readHumidity()
{
    sensor->reset();

    float humidity = 0;
    sensor->getHumidity(&humidity);

    return humidity;
}

void readAccelerator(int accelerator[]) {
    gyro_sensor->getXAxes(accelerator);
}

void readGyroscope(int gyroscope[]) {
    gyro_sensor->getGAxes(gyroscope);
}

// currently unused
float readXSensitivity() {
    float xSensitivity = 0;
    gyro_sensor->getXSensitivity(&xSensitivity);
    
    return xSensitivity;
}

// currently unused
float readGSensitivity() {
    float gSensitivity = 0;
    
    gyro_sensor->getXSensitivity(&gSensitivity);
    
    return gSensitivity;
}

bool readMessage(int messageId, char *payload)
{
    JSON_Value *root_value = json_value_init_object();
    JSON_Object *root_object = json_value_get_object(root_value);
    char *serialized_string = NULL;

    json_object_set_string(root_object, "devId", "ice-guard-1");
    json_object_set_number(root_object, "msgId", messageId);

    float temperature = readTemperature();
    json_object_set_number(root_object, "temp", round_2dp(temperature));

    bool temperatureAlert = false;
    if(temperature > TEMPERATURE_ALERT)
    {
        temperatureAlert = true;
    }

    json_object_set_number(root_object, "hum", round_2dp(readHumidity()));

    // get accelerator data
    int accelerator[3];
    (void)readAccelerator(accelerator);
    // send accelerator details
    json_object_set_number(root_object, "accX", round_2dp(accelerator[0]));
    json_object_set_number(root_object, "accY", round_2dp(accelerator[1]));
    json_object_set_number(root_object, "accZ", round_2dp(accelerator[2]));

    // get gyroscope data
    int gyroscope[3];
    (void)readGyroscope(gyroscope);
    // send gyroscope details
    json_object_set_number(root_object, "gyroX", round_2dp(gyroscope[0]));
    json_object_set_number(root_object, "gyroY", round_2dp(gyroscope[1]));
    json_object_set_number(root_object, "gyroZ", round_2dp(gyroscope[2]));
    
    serialized_string = json_serialize_to_string_pretty(root_value);

    snprintf(payload, MESSAGE_MAX_LEN, "%s", serialized_string);
    json_free_serialized_string(serialized_string);
    json_value_free(root_value);
    return temperatureAlert;
}
