using System;
using System.Collections;
using System.Collections.Generic;
using Unity.VisualScripting;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering.Universal;

public class PilotCamera : MonoBehaviour
{
    [SerializeField] float speed = 5.0f;
    [SerializeField] float rotateSpeed = 2.0f;

    private float _pitch;
    private float _yaw;
    private void OnEnable()
    {
        Camera camera = GetComponent<Camera>();
        if (camera == null) return;
        
        UniversalAdditionalCameraData cameraData = camera.GetUniversalAdditionalCameraData();
        if (cameraData == null) return;
        
        cameraData.requiresDepthTexture = true;
        cameraData.requiresColorTexture = true;
        
        Vector3 eulerAngles = transform.eulerAngles;
        _pitch = eulerAngles.y;
        _yaw = eulerAngles.x;
    }

    // Update is called once per frame
    void Update()
    {
        if (Input.GetMouseButton(1))
        {
            float mouse_x = Input.GetAxis("Mouse X");
            float mouse_y = Input.GetAxis("Mouse Y");
            _yaw += mouse_x * rotateSpeed;
            _pitch -= mouse_y * rotateSpeed;
            _pitch = Mathf.Clamp(_pitch, -90f, 90f);
            transform.rotation = Quaternion.Euler(_pitch, _yaw, 0.0f);
        }
        
        Vector3 moveDir = Vector3.zero;
        if (Input.GetKey(KeyCode.W)) moveDir += transform.forward;
        if (Input.GetKey(KeyCode.A)) moveDir += -transform.right;
        if (Input.GetKey(KeyCode.S)) moveDir += -transform.forward;
        if (Input.GetKey(KeyCode.D)) moveDir += transform.right;
        if (Input.GetKey(KeyCode.Q)) moveDir -= transform.up;
        if (Input.GetKey(KeyCode.E)) moveDir += transform.up;
        
        moveDir.Normalize();
        
        transform.position += moveDir * (speed * Time.deltaTime);
    }
}

[CustomEditor(typeof(PilotCamera))]
public class PilotCameraEditor : Editor
{
    public override void OnInspectorGUI()
    {
        DrawDefaultInspector();
        GUILayout.Space(10);

        if (GUILayout.Button("Align With View"))
        {
            Camera pilot_camera = target.GetComponent<Camera>();
            Camera scene_camera =  SceneView.lastActiveSceneView?.camera;
            if (scene_camera == null) return;
            
            // Ctrl + Z 可以撤回
            Undo.RecordObject(pilot_camera.transform, "Align With View");
            
            pilot_camera.transform.position = scene_camera.transform.position;
            pilot_camera.transform.rotation = scene_camera.transform.rotation;
        }
    }
}