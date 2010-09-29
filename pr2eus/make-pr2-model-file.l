(defun make-pr2-model-file ()
  (let ((robot "pr2") s
        fname_urdf fname_fix_urdf fname_collada fname_yaml fname_lisp)
    (unless (setq s (ros::get-param "/robot_description"))
      (ros::ros-error "could not load model file from /robot_description~%")
      (return-from make-pr2-model-file))

    ;; variable setup
    (setq fname_urdf (format nil "/tmp/~a_~d.urdf" robot (unix::getpid)))
    (setq fname_fix_urdf (format nil "/tmp/~a_~d_fix.urdf" robot (unix::getpid)))
    (setq fname_collada (format nil "/tmp/~a_~d.dae" robot (unix::getpid)))
    (setq fname_yaml (ros::resolve-ros-path (format nil "package://euscollada/~A.yaml" robot)))
    (setq fname_lisp (format nil "/tmp/~a_~d.l" robot (unix::getpid)))

    ;; urdf -> collada -> euslisp
    (unless (probe-file fname_lisp)
      (with-open-file
       (f fname_urdf :direction :output)
       (format f s))

      (unix::system (format nil "sed s/\.dae/\.stl/ < ~A > ~A" fname_urdf fname_fix_urdf))
      (unix::system (format nil "rosrun collada_urdf_jsk_patch urdf_to_collada ~A ~A" fname_fix_urdf fname_collada))
      (unix::system (format nil "rosrun euscollada collada2eus ~A ~A ~A" fname_collada fname_yaml fname_lisp))

      (warning-message 2 "load model file from parameter server /robot_description to ~A~%" fname_lisp)
      )

    ;; camera setup
    (with-open-file
     (f fname_lisp :direction :output :if-exists :append)
     (format f ";;~%")
     (format f ";; additional robot model description from camera_info~%")
     (format f ";;~%")
     (format f "~A~%" (nconc (list 'defun 'make-camera-from-ros-camera-info-aux) (cddddr #'make-camera-from-ros-camera-info-aux)))
     (format f ";;~%")
     (format f "(defmethod ~A-robot~%" robot)
     (dolist (camera-var (list "narrow_stereo/right/camera"
                               "narrow_stereo/left/camera"
                               "wide_stereo/right/camera"
                               "wide_stereo/left/camera"
                               "r_forearm_cam/camera"
                               "l_forearm_cam/camera"))
       (let ((var (intern (substitute #\- #\/ (string-upcase camera-var))))
             (camera-info (format nil "~A_info" camera-var)))
         (ros::subscribe camera-info sensor_msgs::CameraInfo
                         #'(lambda (msg)
                             (set var msg)
                             var))
         (ros::rate 10)
         (while (and (ros::ok) (not (boundp var)))
           (ros::spin-once)
           (ros::sleep))
         (ros::unsubscribe camera-info)
         (setq var (eval var))
         (warning-message 2 "received ~A ~A ~A~%" camera-info var (send var :header :frame_id))
         (format f "  (:~A ()~%" (substitute #\- #\/ (string-downcase camera-var)))
         (format f "   (let ((c (make-camera-from-ros-camera-info-aux ~A ~A ~A))~%" (send var :width) (send var :height) (send var :p))
         (format f "         (f ~A))~%" (send var :header :frame_id))
         (format f "     (send c :name)~%" camera-info)
         (format f "     (send c :newcoords (send f :copy-worldcoords))~%")
         (format f "     (send f :assoc c)~%")
         (format f "     c))~%" camera-info)
         ) ;; let
        ) ;; dolist
     (format f "  ) ;; defmethod ~A-robot~%" robot)
     ) ;; with-open-file
    (warning-message 1 "copy model file from ~A to ~A.l~%" fname_lisp robot)
    (unix::system (format nil "mv ~A ~A.l" fname_lisp robot))
    ))

(ros::roseus "make-pr2-modle-file")
(make-pr2-model-file)

