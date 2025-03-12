luvit make manifest

cd libs

cd weblit
git add .
git commit
git push -u origin HEAD:main
cd ..

cd quickmedia
git add .
git commit
git push -u origin HEAD:main
cd ..

cd ..
git add .
git commit