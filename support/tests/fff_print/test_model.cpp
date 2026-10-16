#include <catch2/catch_test_macros.hpp>

#include "libslic3r/libslic3r.h"
#include "libslic3r/Model.hpp"
#include "libslic3r/Format/3mf.hpp"
#include "libslic3r/Utils.hpp"
#include <arrange-wrapper/ModelArrange.hpp>

#include <boost/nowide/cstdio.hpp>
#include <boost/filesystem.hpp>

#include "test_data.hpp"

using namespace Slic3r;
using namespace Slic3r::Test;

TEST_CASE("Slicer projects retain product and engine versions on round trip", "[Model][3MF]") {
    const auto path = boost::filesystem::temp_directory_path() /
        boost::filesystem::unique_path("slicer-%%%%-%%%%.3mf");
    ScopeGuard cleanup([&path] { boost::filesystem::remove(path); });
    Model original;
    SECTION("A project with a model") {
        auto *object = original.add_object();
        object->add_volume(make_cube(20, 20, 20));
        object->add_instance();
    }
    SECTION("A configuration-only project") {}
    auto config = DynamicPrintConfig::full_print_config();
    REQUIRE(store_3mf(path.string().c_str(), &original, &config, false));
    const auto project = is_project_3mf(path.string());
    REQUIRE(project.first);
    REQUIRE(project.second.has_value());
    REQUIRE(*project.second == *Semver::parse(SLIC3R_VERSION));
    Model restored;
    DynamicPrintConfig restored_config;
    ConfigSubstitutionContext substitutions{ForwardCompatibilitySubstitutionRule::Disable};
    boost::optional<Semver> engine_version;
    REQUIRE(load_3mf(path.string().c_str(), restored_config, substitutions,
        &restored, true, engine_version));
    REQUIRE(restored.objects.size() == original.objects.size());
    REQUIRE(engine_version.has_value());
    REQUIRE(*engine_version == *Semver::parse(SLIC3R_COMPATIBILITY_VERSION));
}

SCENARIO("Model construction", "[Model]") {
    GIVEN("A Slic3r Model") {
		Slic3r::Model model;
        Slic3r::TriangleMesh sample_mesh = Slic3r::make_cube(20,20,20);
        Slic3r::DynamicPrintConfig config = Slic3r::DynamicPrintConfig::full_print_config();
        Slic3r::Print print;

        WHEN("Model object is added") {
            Slic3r::ModelObject *model_object = model.add_object();
            THEN("Model object list == 1") {
                REQUIRE(model.objects.size() == 1);
            }
            model_object->add_volume(sample_mesh);
            THEN("Model volume list == 1") {
                REQUIRE(model_object->volumes.size() == 1);
            }
            THEN("Model volume is a part") {
                REQUIRE(model_object->volumes.front()->is_model_part());
            }
            THEN("Mesh is equivalent to input mesh.") {
                REQUIRE(! sample_mesh.its.vertices.empty());
				const std::vector<Vec3f>& mesh_vertices = model_object->volumes.front()->mesh().its.vertices;
				Vec3f mesh_offset = model_object->volumes.front()->source.mesh_offset.cast<float>();
				for (size_t i = 0; i < sample_mesh.its.vertices.size(); ++ i) {
					const Vec3f &p1 = sample_mesh.its.vertices[i];
					const Vec3f  p2 = mesh_vertices[i] + mesh_offset;
					REQUIRE((p2 - p1).norm() < EPSILON);
				}
            }
            model_object->add_instance();
            arrange_objects(model,
                            arr2::to_arrange_bed(get_bed_shape(config), Point::new_scale(10, 10)),
                            arr2::ArrangeSettings{}.set_distance_from_objects(
                                min_object_distance(config)));

            model_object->ensure_on_bed();
			print.auto_assign_extruders(model_object);
			THEN("Print works?") {
				print.set_status_silent();
				print.apply(model, config);
				print.process();
				boost::filesystem::path temp = boost::filesystem::unique_path();
                print.export_gcode(temp.string(), nullptr, nullptr);
                REQUIRE(boost::filesystem::exists(temp));
				REQUIRE(boost::filesystem::is_regular_file(temp));
				REQUIRE(boost::filesystem::file_size(temp) > 0);
				boost::nowide::remove(temp.string().c_str());
			}
        }
    }
}
