//
//  ViewController.swift
//  CameraProcessing
//

import UIKit
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet weak var ImageView: UIImageView!
    var previewImage = UIImage()
    
    // coordinates between input and output
    let captureSession = AVCaptureSession()
    
    // display cameraview in viewcontroller
    var previewLayer:CALayer!
    var captureDevice:AVCaptureDevice!

    override func viewDidLoad() {
        super.viewDidLoad()
        prepareCamera()
        
        // Set license for VisageSDK.
        Tracker.setUpLicense()
        
        // Run camera after 1 second.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: {
            _ = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(self.setPreviewImage), userInfo: nil, repeats: true)
        })
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func prepareCamera() {
        // Preset.Photo gets the best configuration of the photo
        captureSession.sessionPreset = AVCaptureSession.Preset.photo
        
        let availableDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .front).devices
        if availableDevices.count > 0 {
            captureDevice = availableDevices.first
            beginSession()
        }
    }
    
    func beginSession() {
        do {
            let captureDeviceInput = try AVCaptureDeviceInput(device: captureDevice)
            captureSession.addInput(captureDeviceInput)
        }catch {
            print(error.localizedDescription)
        }
        
//        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
//        self.previewLayer = previewLayer
//        self.view.layer.addSublayer(self.previewLayer)
//        self.previewLayer.frame = self.view.layer.frame
        captureSession.startRunning()
        
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString):NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
        dataOutput.alwaysDiscardsLateVideoFrames = true
        
        if captureSession.canAddOutput(dataOutput) {
            captureSession.addOutput(dataOutput)
        }
        
        captureSession.commitConfiguration()
        
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
    }
    
    // This function is called all the time when captureSession is running.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        connection.videoOrientation = AVCaptureVideoOrientation.portrait;
        previewImage = getImageFromSampleBuffer(buffer: sampleBuffer)
    }
    
    func getImageFromSampleBuffer(buffer:CMSampleBuffer) -> UIImage {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(buffer){
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            
            // Set the dimention of the image we want to display later
            let imageRec = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            
            if let image = context.createCGImage(ciImage, from: imageRec) {
                return UIImage(cgImage: image, scale: 1.0, orientation: UIImage.Orientation.right)
            }
        }
        
        return UIImage()
    }
    
    @objc func setPreviewImage(){
        //ImageView.image = previewImage
        ImageView.image = OpenCVWrapper.makeGrayof(previewImage)
    }
}

